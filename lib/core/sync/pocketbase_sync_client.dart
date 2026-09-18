import 'package:pocketbase/pocketbase.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

const _identityKey = 'account_identity';
const _tokenKey = 'account_token';

/// Talks to a self-hosted PocketBase instance: account registration/login
/// and the push/pull operations [SyncEngine] needs.
class PocketBaseSyncClient implements SyncBackend {
  /// Creates a [PocketBaseSyncClient] talking to the PocketBase instance
  /// at [baseUrl], persisting sessions/cursors via [settings].
  new({required String baseUrl, required this.settings})
    : _pb = PocketBase(baseUrl);

  final PocketBase _pb;

  /// Where sessions/cursors are persisted — also read by [SyncEngine]'s
  /// caller for its own cursor bookkeeping.
  final AppSettingsRepository settings;

  /// Registers a new account with [email]/[password], authenticates, and
  /// persists the session.
  Future<void> register(String email, String password) async {
    await _pb
        .collection('users')
        .create(
          body: {
            'email': email,
            'password': password,
            'passwordConfirm': password,
          },
        );
    await _authenticate(email, password);
  }

  /// Authenticates as an existing account, entered by the user.
  Future<void> login(String email, String password) =>
      _authenticate(email, password);

  Future<void> _authenticate(String email, String password) async {
    final auth = await _pb
        .collection('users')
        .authWithPassword(email, password);
    await settings.setValue(_identityKey, email);
    await settings.setValue(_tokenKey, auth.token);
    _pb.authStore.save(auth.token, auth.record);
  }

  /// Clears this device's stored session (identity/token) and PocketBase
  /// auth state, without touching any local sembast data — see
  /// `account_service.dart`'s `logout()` for the full "return to guest
  /// mode" flow, which calls this as one step.
  Future<void> clearSession() async {
    await settings.deleteValue(_identityKey);
    await settings.deleteValue(_tokenKey);
    _pb.authStore.clear();
  }

  /// The logged-in account's email, or `null` if there's no session
  /// (guest mode, or the stored session was never successfully
  /// restored/refreshed).
  Future<String?> currentEmail() => settings.getValue(_identityKey);

  /// Restores a previously-saved auth session, if any, so the app
  /// doesn't need to log in on every restart. Also attempts to refresh
  /// the token against PocketBase (tokens expire — PocketBase's default
  /// is roughly 2 weeks — and a silently-dead session would otherwise
  /// stop syncing forever with no way to recover short of logging in
  /// again). Returns whether a valid, usable session was restored.
  Future<bool> restoreSession() async {
    final token = await settings.getValue(_tokenKey);
    if (token == null) return false;
    _pb.authStore.save(token, null);
    if (!_pb.authStore.isValid) return false;

    try {
      final auth = await _pb.collection('users').authRefresh();
      await settings.setValue(_tokenKey, auth.token);
      _pb.authStore.save(auth.token, auth.record);
      return true;
    } on Object {
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
  String _requireOwner() {
    final owner = _pb.authStore.record?.id;
    if (owner == null) {
      throw StateError('Not logged in: no authenticated account session.');
    }
    return owner;
  }

  @override
  Future<void> upsert(String collection, Map<String, Object?> record) async {
    final entityId = record['id']! as String;
    final owner = _requireOwner();

    final body = {
      'entity_id': entityId,
      'owner': owner,
      'updated_at': record['updatedAt'],
      'deleted': record['deleted'] ?? false,
      'data': record,
    };

    final existing = await _pb
        .collection(collection)
        .getList(
          page: 1,
          perPage: 1,
          filter: 'entity_id = "$entityId" && owner = "$owner"',
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
    _requireOwner();
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
