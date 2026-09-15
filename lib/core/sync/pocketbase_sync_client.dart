import 'dart:math';

import 'package:pocketbase/pocketbase.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I

/// A random 6-character pairing code, e.g. `K7QX2P`. Excludes visually
/// ambiguous characters (0/O, 1/I) since a person types this by hand.
String generatePairingCode() {
  final random = Random.secure();
  return List.generate(
    6,
    (_) => _codeAlphabet[random.nextInt(_codeAlphabet.length)],
  ).join();
}

const _identityKey = 'sync_group_identity';
const _tokenKey = 'sync_group_token';

/// Talks to a self-hosted PocketBase instance: pairing (create/join a
/// sync group) and the push/pull operations [SyncEngine] needs.
class PocketBaseSyncClient implements SyncBackend {
  PocketBaseSyncClient({required String baseUrl, required this.settings})
    : _pb = PocketBase(baseUrl);

  final PocketBase _pb;
  final AppSettingsRepository settings;

  /// Creates a new sync group with a fresh pairing code, authenticates
  /// as it, and returns the code for the user to share with other
  /// devices.
  Future<String> createGroup() async {
    final code = generatePairingCode();
    await _pb
        .collection('sync_groups')
        .create(
          body: {'username': code, 'password': code, 'passwordConfirm': code},
        );
    await _authenticate(code);
    return code;
  }

  /// Authenticates as the sync group identified by [code], entered by
  /// the user from another device.
  Future<void> joinGroup(String code) => _authenticate(code);

  Future<void> _authenticate(String code) async {
    final auth = await _pb
        .collection('sync_groups')
        .authWithPassword(code, code);
    await settings.setValue(_identityKey, code);
    await settings.setValue(_tokenKey, auth.token);
    _pb.authStore.save(auth.token, auth.record);
  }

  /// Restores a previously-saved auth session, if any, so the app
  /// doesn't need to re-pair on every restart. Also attempts to refresh
  /// the token against PocketBase (tokens expire — PocketBase's default
  /// is roughly 2 weeks — and a silently-dead session would otherwise
  /// stop syncing forever with no way to recover short of re-pairing).
  /// Returns whether a valid, usable session was restored.
  Future<bool> restoreSession() async {
    final token = await settings.getValue(_tokenKey);
    if (token == null) return false;
    _pb.authStore.save(token, null);
    if (!_pb.authStore.isValid) return false;

    try {
      final auth = await _pb.collection('sync_groups').authRefresh();
      await settings.setValue(_tokenKey, auth.token);
      _pb.authStore.save(auth.token, auth.record);
      return true;
    } catch (_) {
      // Refresh failed - the session is genuinely dead (expired/revoked).
      // Leave the stale token in place; callers should treat this as "no
      // usable session" without throwing out of restoreSession.
      return false;
    }
  }

  /// Formats [dt] the way PocketBase's own `updated`/`created` autodate
  /// fields are formatted (space-separated, not the `T`-separated form
  /// [DateTime.toIso8601String] produces) — PocketBase's filter parser
  /// only recognizes its own format as a datetime literal; a `T`-separated
  /// value silently matches nothing instead of erroring.
  String _filterDateTime(DateTime dt) =>
      dt.toUtc().toIso8601String().replaceFirst('T', ' ');

  /// Requires an authenticated session, throwing rather than silently
  /// no-op'ing. A caller (e.g. [SyncEngine]) that silently succeeded with
  /// no session would wrongly treat unsynced records as pushed, advancing
  /// its cursor past them and losing them permanently.
  String _requireSyncGroup() {
    final syncGroup = _pb.authStore.record?.id;
    if (syncGroup == null) {
      throw StateError('Not paired: no authenticated sync group session.');
    }
    return syncGroup;
  }

  @override
  Future<void> upsert(String collection, Map<String, Object?> record) async {
    final entityId = record['id']! as String;
    final syncGroup = _requireSyncGroup();

    final body = {
      'entity_id': entityId,
      'sync_group': syncGroup,
      'updated_at': record['updatedAt'],
      'deleted': record['deleted'] ?? false,
      'data': record,
    };

    final existing = await _pb
        .collection(collection)
        .getList(
          page: 1,
          perPage: 1,
          filter: 'entity_id = "$entityId" && sync_group = "$syncGroup"',
        );
    if (existing.items.isEmpty) {
      await _pb.collection(collection).create(body: body);
    } else {
      await _pb
          .collection(collection)
          .update(existing.items.first.id, body: body);
    }
  }

  @override
  Future<List<Map<String, Object?>>> listChangedSince(
    String collection,
    DateTime cursor,
  ) async {
    _requireSyncGroup();
    final result = await _pb
        .collection(collection)
        .getList(
          page: 1,
          perPage: 200,
          filter: 'updated > "${_filterDateTime(cursor)}"',
          sort: 'updated',
        );
    return [
      for (final item in result.items)
        {
          'entity_id': item.data['entity_id'],
          'updated_at': item.data['updated_at'],
          'server_updated': item.get<String>('updated'),
          'deleted': item.data['deleted'],
          'data': item.data['data'],
        },
    ];
  }
}
