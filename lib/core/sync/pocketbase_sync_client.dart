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
  /// doesn't need to re-pair on every restart. Returns whether a session
  /// was restored.
  Future<bool> restoreSession() async {
    final token = await settings.getValue(_tokenKey);
    if (token == null) return false;
    _pb.authStore.save(token, null);
    return _pb.authStore.isValid;
  }

  @override
  Future<void> upsert(String collection, Map<String, Object?> record) async {
    final entityId = record['id']! as String;
    final syncGroup = _pb.authStore.record?.id;
    if (syncGroup == null) return;

    final body = {
      'entity_id': entityId,
      'sync_group': syncGroup,
      'updated_at': record['updatedAt'],
      'deleted': record['deleted'] ?? false,
      'data': record,
    };

    final existing = await _pb
        .collection(collection)
        .getList(page: 1, perPage: 1, filter: 'entity_id = "$entityId"');
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
    final result = await _pb
        .collection(collection)
        .getList(
          page: 1,
          perPage: 200,
          filter: 'updated_at > "${cursor.toIso8601String()}"',
          sort: 'updated_at',
        );
    return [
      for (final item in result.items)
        {
          'entity_id': item.data['entity_id'],
          'updated_at': item.data['updated_at'],
          'deleted': item.data['deleted'],
          'data': item.data['data'],
        },
    ];
  }
}
