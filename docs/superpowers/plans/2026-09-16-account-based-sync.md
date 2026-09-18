# Account-Based Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace taskframe's pairing-code sync identity with real PocketBase email/password accounts, keeping the app fully usable local-only without one (guest mode), and merging a guest's local data into whichever account they register for or log into.

**Architecture:** The existing `SyncEngine`/`SyncBackend`/six-collection push-pull-LWW machinery is untouched. Only the identity layer changes: `PocketBaseSyncClient` swaps pairing-code create/join for email/password register/login against a real PocketBase `users` auth collection; the `sync_group` field/rule on every data collection is renamed `owner`. Guest mode needs no new code — `SyncEngine` already treats "unauthenticated" as a retryable failure, and a freshly-authenticated device's cursors starting at epoch is what pushes/pulls a guest's local data into the account on the very next sync. A new `logout()` clears local synced data, cursors, and the session.

**Tech Stack:** Flutter/Dart, `pocketbase` Dart SDK, self-hosted PocketBase (existing).

**Spec:** `docs/superpowers/specs/2026-09-16-account-based-sync-design.md` (supersedes `2026-09-15-sync-backend-design.md`'s pairing-code decision; everything else in that spec — PocketBase, the six collections, `SyncEngine`'s LWW logic, sync triggers — is unchanged and this plan builds on the existing implementation)

## Global Constraints

- Identity is a real PocketBase `users` auth collection (email + password) — no pairing codes, no `sync_groups` collection.
- Guest mode is not a new mechanism: an unauthenticated device already works entirely off local sembast (`SyncEngine.syncAll` swallows the "not logged in" throw and retries later).
- No separate migration step: because a freshly-authenticated device's push/pull cursors start at epoch, the very next sync after register/login naturally uploads all local guest data and downloads whatever the account already has.
- Logout wipes local synced data (all six sembast stores + sync cursors + session), but never touches unrelated settings (e.g. the install-hint flag) or the PocketBase account/server-side data.
- No email verification, no password reset in this pass.

---

## File Structure

New files:
- `lib/core/sync/account_service.dart` — `logout()`, composing a full "return to guest mode" flow
- `lib/features/account/account_providers.dart` — replaces `lib/features/pairing/pairing_providers.dart`
- `lib/features/account/widgets/account_screen.dart` — replaces `lib/features/pairing/widgets/pairing_screen.dart`
- `test/unit/account_service_test.dart`
- `test/widget/account_screen_test.dart` — replaces `test/widget/pairing_screen_test.dart`

Deleted files (each removed in the task that replaces its functionality — see task steps):
- `lib/features/pairing/pairing_providers.dart` → `lib/features/account/account_providers.dart`
- `lib/features/pairing/widgets/pairing_screen.dart` → `lib/features/account/widgets/account_screen.dart`
- `test/widget/pairing_screen_test.dart` → `test/widget/account_screen_test.dart`
- `test/unit/pocketbase_sync_client_test.dart` — its only content, `generatePairingCode()`'s pure-logic tests, has no equivalent once pairing codes are removed; `register`/`login` need a real PocketBase to test meaningfully, which is exactly what `test/integration/pocketbase_sync_test.dart` (Task 6) already provides and is being retargeted for anyway

Modified files:
- `scripts/setup_pocketbase.dart` — `sync_groups` auth collection → `users`; `sync_group` field → `owner` on all six data collections
- `lib/core/sync/pocketbase_sync_client.dart` — `register`/`login`/`clearSession`/`currentEmail` replace `generatePairingCode`/`createGroup`/`joinGroup`; `owner` replaces `sync_group`
- `lib/core/storage/app_settings_repository.dart` — add `deleteValue`
- `lib/core/widgets/app_shell.dart` — nav entry relabeled "Account", routes to `/account`
- `lib/router.dart` — `/pairing` → `/account`
- `lib/main.dart` — wires `accountLogoutProvider`
- `test/widget/app_shell_test.dart` — route/label updates
- `test/integration/pocketbase_sync_test.dart` — retargeted to `register`/`login`, plus new register/merge/logout scenarios

---

### Task 1: PocketBase collection migration (`users` replaces `sync_groups`, `owner` replaces `sync_group`)

**Files:**
- Modify: `scripts/setup_pocketbase.dart`

**Interfaces:**
- Produces: a `users` auth collection (email identity, public self-registration, PocketBase's default password rules) and six data collections whose `owner` field/API rules/unique index replace `sync_group`. Task 2's `PocketBaseSyncClient` targets exactly these names/fields.

- [ ] **Step 1: Update `baseCollection()`'s field/index/rule names**

```dart
// scripts/setup_pocketbase.dart
Map<String, Object?> baseCollection(String name) => {
  'name': name,
  'type': 'base',
  'fields': [
    {'name': 'entity_id', 'type': 'text', 'required': true},
    {'name': 'owner', 'type': 'text', 'required': true},
    {'name': 'updated_at', 'type': 'text', 'required': true},
    {'name': 'deleted', 'type': 'bool', 'required': false},
    {'name': 'data', 'type': 'json', 'required': true},
    // PocketBase no longer auto-adds `created`/`updated` unless they're
    // explicitly declared as autodate fields. `updated` is what
    // PocketBaseSyncClient.listChangedSince/SyncEngine._pull use as the
    // pull cursor (server-managed, immune to client clock skew) — see
    // the sync design doc's data flow.
    {'name': 'created', 'type': 'autodate', 'onCreate': true},
    {
      'name': 'updated',
      'type': 'autodate',
      'onCreate': true,
      'onUpdate': true,
    },
  ],
  'indexes': [
    'CREATE INDEX idx_${name}_owner_updated ON $name (owner, updated_at)',
    'CREATE UNIQUE INDEX idx_${name}_entity ON $name (owner, entity_id)',
  ],
  'listRule': 'owner = @request.auth.id',
  'viewRule': 'owner = @request.auth.id',
  'createRule': 'owner = @request.auth.id',
  'updateRule': 'owner = @request.auth.id',
  'deleteRule': 'owner = @request.auth.id',
};
```

- [ ] **Step 2: Replace the `sync_groups` collection definition with `users`**

In the `collections` list passed to the import call, replace the entire `sync_groups` map literal with:

```dart
{
  'name': 'users',
  'type': 'auth',
  // Real accounts: standard PocketBase auth-collection posture, unlike
  // the old pairing-code collection — public self-registration
  // (createRule: '' — anyone can sign up, same posture PocketBase
  // ships by default for a fresh auth collection's create), email as
  // the identity field, and PocketBase's default password rules (min
  // 8) instead of the old 6-char minimum that only existed to match
  // 6-character pairing codes.
  'createRule': '',
  'fields': [
    {'name': 'email', 'type': 'email', 'required': true},
    {'name': 'password', 'type': 'password', 'required': true, 'min': 8},
  ],
  'passwordAuth': {
    'enabled': true,
    'identityFields': ['email'],
  },
},
```

Note for the executor: PocketBase auth collections typically enforce email uniqueness by default without a manual index (unlike the old `sync_groups` collection's `username` field, which needed an explicit `CREATE UNIQUE INDEX` because it was a plain text field repurposed as identity). Verify this empirically in Step 4 by attempting to register the same email twice — if PocketBase doesn't reject the second attempt, add `'indexes': ['CREATE UNIQUE INDEX idx_users_email ON users (email)']` to this collection definition and re-run.

Update the top-of-file comment (`// One-time setup: creates the sync_groups auth collection...`) to say `users` instead of `sync_groups`, and the file's usage/purpose comments generally — read through the whole file and fix every remaining `sync_group`/pairing reference in comments, not just the code.

- [ ] **Step 3: Reset the local PocketBase and re-run setup**

Run: `docker compose down -v && docker compose up -d --build pocketbase`
Run: `docker compose exec pocketbase /pb/pocketbase superuser upsert dev@taskframe.local dev-password-change-me`
Run: `dart run scripts/setup_pocketbase.dart http://localhost:8090 dev@taskframe.local dev-password-change-me`
Expected: `PocketBase collections created.`

- [ ] **Step 4: Verify live**

Run: `curl -s http://localhost:8090/api/collections/users | python3 -m json.tool` — confirm `type: "auth"`, `createRule: ""`, an `email` field, `passwordAuth.identityFields: ["email"]`.
Run: `curl -s http://localhost:8090/api/collections/tasks | python3 -m json.tool` — confirm the `owner` field exists (not `sync_group`), and `listRule`/`viewRule`/`createRule`/`updateRule`/`deleteRule` are all `"owner = @request.auth.id"`.
Run (per the Step 2 note): register the same email twice via `curl -X POST http://localhost:8090/api/collections/users/records -H "Content-Type: application/json" -d '{"email":"dup@test.local","password":"testpass123","passwordConfirm":"testpass123"}'` twice in a row — the second attempt should fail with a validation error (email already taken). If it doesn't, add the unique index per Step 2's note, reset, and re-verify.

- [ ] **Step 5: Commit**

```bash
git add scripts/setup_pocketbase.dart
git commit -m "feat: replace sync_groups pairing collection with a real users auth collection"
```

---

### Task 2: `AppSettingsRepository.deleteValue`

**Files:**
- Modify: `lib/core/storage/app_settings_repository.dart`
- Test: `test/unit/app_settings_repository_test.dart`

**Interfaces:**
- Produces: `AppSettingsRepository.deleteValue(String key) -> Future<void>`, on both `InMemoryAppSettingsRepository` and `SembastAppSettingsRepository`. Task 4's `logout()` uses this to clear sync cursors and the session; unrelated keys (e.g. the install-hint flag) are left alone by only ever being passed their own specific keys.

- [ ] **Step 1: Write the failing tests**

```dart
// test/unit/app_settings_repository_test.dart — add to the InMemoryAppSettingsRepository group
test('deleteValue removes a previously-set value', () async {
  final repository = InMemoryAppSettingsRepository();
  await repository.setValue('sync_pull_tasks', '2026-09-15T00:00:00.000Z');

  await repository.deleteValue('sync_pull_tasks');

  expect(await repository.getValue('sync_pull_tasks'), isNull);
});

test('deleteValue on an unset key is a no-op', () async {
  final repository = InMemoryAppSettingsRepository();
  await repository.deleteValue('missing'); // should not throw
  expect(await repository.getValue('missing'), isNull);
});
```

```dart
// test/unit/app_settings_repository_test.dart — add to the SembastAppSettingsRepository group
test('deleteValue removes a previously-set value', () async {
  await repository.setValue('sync_pull_tasks', '2026-09-15T00:00:00.000Z');

  await repository.deleteValue('sync_pull_tasks');

  expect(await repository.getValue('sync_pull_tasks'), isNull);
});

test('deleteValue on an unset key is a no-op', () async {
  await repository.deleteValue('missing'); // should not throw
  expect(await repository.getValue('missing'), isNull);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/unit/app_settings_repository_test.dart`
Expected: FAIL — `deleteValue` not defined.

- [ ] **Step 3: Implement**

```dart
// lib/core/storage/app_settings_repository.dart — extend the interface and both implementations
abstract class AppSettingsRepository {
  Future<DateTime?> getInstallHintDismissedAt();
  Future<void> setInstallHintDismissedAt(DateTime time);
  Future<String?> getValue(String key);
  Future<void> setValue(String key, String value);

  /// Removes any stored value under [key]. A no-op if nothing was
  /// stored there.
  Future<void> deleteValue(String key);
}

class InMemoryAppSettingsRepository implements AppSettingsRepository {
  DateTime? _dismissedAt;
  final Map<String, String> _values = {};

  @override
  Future<DateTime?> getInstallHintDismissedAt() async => _dismissedAt;

  @override
  Future<void> setInstallHintDismissedAt(DateTime time) async {
    _dismissedAt = time;
  }

  @override
  Future<String?> getValue(String key) async => _values[key];

  @override
  Future<void> setValue(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> deleteValue(String key) async {
    _values.remove(key);
  }
}

class SembastAppSettingsRepository implements AppSettingsRepository {
  new(this._db);

  final Database _db;

  static const _key = 'install_hint_dismissed_at';

  @override
  Future<DateTime?> getInstallHintDismissedAt() async {
    final record = await settingsStore.record(_key).get(_db);
    final iso = record?['value'] as String?;
    return iso == null ? null : DateTime.parse(iso);
  }

  @override
  Future<void> setInstallHintDismissedAt(DateTime time) async {
    await settingsStore.record(_key).put(_db, {
      'value': time.toIso8601String(),
    });
  }

  @override
  Future<String?> getValue(String key) async {
    final record = await settingsStore.record(key).get(_db);
    return record?['value'] as String?;
  }

  @override
  Future<void> setValue(String key, String value) async {
    await settingsStore.record(key).put(_db, {'value': value});
  }

  @override
  Future<void> deleteValue(String key) async {
    await settingsStore.record(key).delete(_db);
  }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/unit/app_settings_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/storage/app_settings_repository.dart test/unit/app_settings_repository_test.dart
git commit -m "feat: add deleteValue to AppSettingsRepository"
```

---

### Task 3: `PocketBaseSyncClient` — register/login replace pairing, `owner` replaces `sync_group`

**Files:**
- Modify: `lib/core/sync/pocketbase_sync_client.dart`
- Delete: `test/unit/pocketbase_sync_client_test.dart` (see File Structure — no pure-logic surface remains to unit test once `generatePairingCode` is gone; `register`/`login` get real coverage from the integration tests in Task 6)

**Interfaces:**
- Consumes: `AppSettingsRepository.deleteValue` (Task 2).
- Produces: `PocketBaseSyncClient.register(String email, String password) -> Future<void>`, `.login(String email, String password) -> Future<void>`, `.clearSession() -> Future<void>` (clears the stored session/PocketBase auth state only — no local sembast data), `.currentEmail() -> Future<String?>` (the logged-in account's email, or `null` if none). `.restoreSession()`/`.upsert()`/`.listChangedSince()` keep their existing signatures (still implement `SyncBackend`), just targeting `users`/`owner` instead of `sync_groups`/`sync_group`. Task 4's `logout()` calls `.clearSession()`; Task 5's `AccountNotifier` calls `.register()`/`.login()`/`.currentEmail()` (via `.restoreSession()`).

- [ ] **Step 1: Delete the pairing-code unit test file**

```bash
git rm test/unit/pocketbase_sync_client_test.dart
```

- [ ] **Step 2: Rewrite the client**

```dart
// lib/core/sync/pocketbase_sync_client.dart
import 'package:pocketbase/pocketbase.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

const _identityKey = 'account_identity';
const _tokenKey = 'account_token';

/// Talks to a self-hosted PocketBase instance: account registration/login
/// and the push/pull operations [SyncEngine] needs.
class PocketBaseSyncClient implements SyncBackend {
  PocketBaseSyncClient({required String baseUrl, required this.settings})
    : _pb = PocketBase(baseUrl);

  final PocketBase _pb;
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
```

- [ ] **Step 3: Verify it compiles and the rest of the suite still passes**

Run: `flutter analyze lib/core/sync/pocketbase_sync_client.dart`
Expected: no errors (other files that reference the old `createGroup`/`joinGroup`/`generatePairingCode` API — `lib/features/pairing/...` — will fail to compile until Tasks 4-7 update them; that's expected and resolved by the end of this plan, not this task. Confirm via `flutter analyze lib/core/sync/pocketbase_sync_client.dart` scoped to just this file rather than the whole project for this step.)

- [ ] **Step 4: Commit**

```bash
git add lib/core/sync/pocketbase_sync_client.dart test/unit/pocketbase_sync_client_test.dart
git commit -m "feat: replace pairing-code create/join with register/login on PocketBaseSyncClient"
```

---

### Task 4: `logout()` — return to guest mode

**Files:**
- Create: `lib/core/sync/account_service.dart`
- Test: `test/unit/account_service_test.dart`

**Interfaces:**
- Consumes: `syncCollections` (`lib/core/sync/sync_collection.dart`, existing), `AppSettingsRepository.deleteValue` (Task 2), `PocketBaseSyncClient.clearSession()` (Task 3).
- Produces: `Future<void> logout({required Database db, required AppSettingsRepository settings, required PocketBaseSyncClient client})`. Task 7's `main.dart` wires this into `accountLogoutProvider` (Task 5).

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/account_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/account_service.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';

void main() {
  test(
    'logout clears every synced store, every sync cursor, and the '
    'session, but leaves unrelated settings alone',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      final settings = SembastAppSettingsRepository(db);
      final client = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: settings,
      );

      // Seed data in every synced store, a couple of sync cursors, a
      // session, and one unrelated setting.
      await tasksStore.record('t1').put(db, {'id': 't1', 'title': 'x'});
      await categoriesStore.record('c1').put(db, {'id': 'c1', 'name': 'x'});
      await templatesStore.record('tpl1').put(db, {'id': 'tpl1'});
      await templateBlocksStore.record('tb1').put(db, {'id': 'tb1'});
      await savedSearchesStore.record('s1').put(db, {'id': 's1'});
      await dayBlocksStore.record('d1').put(db, {'id': 'd1'});
      await settings.setValue('sync_push_tasks', '2026-01-01T00:00:00.000Z');
      await settings.setValue('sync_pull_tasks', '2026-01-01T00:00:00.000Z');
      await settings.setValue('account_identity', 'me@example.com');
      await settings.setValue('account_token', 'a-token');
      await settings.setInstallHintDismissedAt(DateTime(2026, 1, 1));

      await logout(db: db, settings: settings, client: client);

      expect(await tasksStore.record('t1').get(db), isNull);
      expect(await categoriesStore.record('c1').get(db), isNull);
      expect(await templatesStore.record('tpl1').get(db), isNull);
      expect(await templateBlocksStore.record('tb1').get(db), isNull);
      expect(await savedSearchesStore.record('s1').get(db), isNull);
      expect(await dayBlocksStore.record('d1').get(db), isNull);
      expect(await settings.getValue('sync_push_tasks'), isNull);
      expect(await settings.getValue('sync_pull_tasks'), isNull);
      expect(await settings.getValue('account_identity'), isNull);
      expect(await settings.getValue('account_token'), isNull);
      expect(
        await settings.getInstallHintDismissedAt(),
        DateTime(2026, 1, 1),
      );
    },
  );
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/account_service_test.dart`
Expected: FAIL — `logout` not defined.

- [ ] **Step 3: Implement**

```dart
// lib/core/sync/account_service.dart
import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_collection.dart';

/// Returns this device to a clean guest state: clears every synced
/// sembast store, every push/pull sync cursor, and the stored account
/// session — but leaves unrelated settings (e.g. the install-hint
/// dismissal flag) and the PocketBase account/server-side data
/// untouched. Logging back in re-pulls everything from the account.
Future<void> logout({
  required Database db,
  required AppSettingsRepository settings,
  required PocketBaseSyncClient client,
}) async {
  for (final collection in syncCollections) {
    await collection.store.delete(db);
    await settings.deleteValue('sync_push_${collection.name}');
    await settings.deleteValue('sync_pull_${collection.name}');
  }
  await client.clearSession();
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/unit/account_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/account_service.dart test/unit/account_service_test.dart
git commit -m "feat: add logout(), clearing local synced data and the account session"
```

---

### Task 5: `account_providers.dart` (replaces `pairing_providers.dart`)

**Files:**
- Create: `lib/features/account/account_providers.dart`
- Delete: `lib/features/pairing/pairing_providers.dart`

**Interfaces:**
- Consumes: `PocketBaseSyncClient.register`/`.login`/`.restoreSession`/`.currentEmail` (Task 3), `logout()` (Task 4).
- Produces: `pocketBaseBaseUrl` (unchanged), `pocketBaseBaseUrlProvider` (unchanged), `pocketBaseSyncClientProvider` (unchanged), `accountLogoutProvider` (`Provider<Future<void> Function()>`, thrown by default — Task 7's `main.dart` overrides it), `AccountNotifier extends AsyncNotifier<String?>` (state is the logged-in email, or `null` for guest mode) with `register(String, String)`/`login(String, String)`/`logout()`, and `accountProvider = AsyncNotifierProvider<AccountNotifier, String?>`. Task 6's `AccountScreen` reads `accountProvider`/`accountProvider.notifier`.

- [ ] **Step 1: Delete the old file, create the new one**

```bash
git rm lib/features/pairing/pairing_providers.dart
```

```dart
// lib/features/account/account_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';

/// The PocketBase base URL. Defaults to `/` (same-origin) — nginx
/// (`nginx.conf`) proxies `/api/` to the `pocketbase` service, so the web
/// app never needs to know PocketBase's real host. Override at build time
/// with `--dart-define=POCKETBASE_URL=...` for a deployment where the app
/// isn't served through that proxy (e.g. a native build talking to a
/// PocketBase host directly).
const pocketBaseBaseUrl = String.fromEnvironment(
  'POCKETBASE_URL',
  defaultValue: '/',
);

/// Riverpod-accessible form of [pocketBaseBaseUrl], for widgets/tests.
final pocketBaseBaseUrlProvider = Provider<String>(
  (ref) => pocketBaseBaseUrl,
);

final pocketBaseSyncClientProvider = Provider<PocketBaseSyncClient>((ref) {
  throw UnimplementedError(
    'Override with a PocketBaseSyncClient built from appSettingsRepositoryProvider '
    'at the composition root — see sembastOverrides in main.dart.',
  );
});

/// Runs the full "return to guest mode" flow (`logout()` in
/// `account_service.dart`, which needs the raw [Database] this provider
/// doesn't have direct access to). Overridden at the composition root,
/// where that database is available — see `main.dart`.
final accountLogoutProvider = Provider<Future<void> Function()>((ref) {
  throw UnimplementedError(
    'Override with a closure calling logout(...) at the composition root '
    '— see main.dart.',
  );
});

/// This device's account state: the logged-in email, or `null` for guest
/// mode. Also exposes the actions to register/log in/log out.
class AccountNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final client = ref.watch(pocketBaseSyncClientProvider);
    final restored = await client.restoreSession();
    return restored ? client.currentEmail() : null;
  }

  /// Registers a new account, uploading any local guest data to it on
  /// the next sync (no separate migration step — see the design doc).
  Future<void> register(String email, String password) async {
    await ref.read(pocketBaseSyncClientProvider).register(email, password);
    state = AsyncData(email);
  }

  /// Logs into an existing account, merging local guest data into it on
  /// the next sync.
  Future<void> login(String email, String password) async {
    await ref.read(pocketBaseSyncClientProvider).login(email, password);
    state = AsyncData(email);
  }

  /// Returns to guest mode: clears local synced data/cursors/session.
  Future<void> logout() async {
    await ref.read(accountLogoutProvider)();
    state = const AsyncData(null);
  }
}

final accountProvider = AsyncNotifierProvider<AccountNotifier, String?>(
  AccountNotifier.new,
);
```

Note for the executor: `client.currentEmail()` returns a `Future<String?>`, but `build()` needs a `String?` after `await`ing it — write `return restored ? await client.currentEmail() : null;` (the snippet above omits the `await` by mistake; add it).

- [ ] **Step 2: Verify it compiles in isolation**

Run: `flutter analyze lib/features/account/account_providers.dart`
Expected: no errors. (Other files still referencing `lib/features/pairing/...` will fail project-wide analysis until Tasks 6-7 — that's expected at this point in the plan.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/account/account_providers.dart lib/features/pairing/pairing_providers.dart
git commit -m "feat: add account_providers.dart, replacing pairing_providers.dart"
```

---

### Task 6: `account_screen.dart` (replaces `pairing_screen.dart`)

**Files:**
- Create: `lib/features/account/widgets/account_screen.dart`
- Create: `test/widget/account_screen_test.dart`
- Delete: `lib/features/pairing/widgets/pairing_screen.dart`
- Delete: `test/widget/pairing_screen_test.dart`

**Interfaces:**
- Consumes: `accountProvider`/`AccountNotifier` (Task 5).
- Produces: `AccountScreen` widget. Task 7's `router.dart` routes `/account` to it.

- [ ] **Step 1: Delete the old files**

```bash
git rm lib/features/pairing/widgets/pairing_screen.dart test/widget/pairing_screen_test.dart
```

- [ ] **Step 2: Write the failing tests**

```dart
// test/widget/account_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/features/account/account_providers.dart';
import 'package:taskframe/features/account/widgets/account_screen.dart';

/// An [AccountNotifier] whose [login] always fails, standing in for
/// wrong credentials without depending on a real PocketBase server —
/// keeps this a deterministic, network-free widget test. [build] is
/// also overridden so it never touches [pocketBaseSyncClientProvider].
class _FailingLoginAccountNotifier extends AccountNotifier {
  @override
  Future<String?> build() async => null;

  @override
  Future<void> login(String email, String password) async {
    throw StateError('invalid credentials');
  }
}

/// An [AccountNotifier] that reports an already-logged-in state, for
/// testing the logged-in view without a real session.
class _LoggedInAccountNotifier extends AccountNotifier {
  @override
  Future<String?> build() async => 'me@example.com';

  @override
  Future<void> logout() async {
    state = const AsyncData(null);
  }
}

void main() {
  testWidgets('guest mode shows register/login form controls', (
    tester,
  ) async {
    final client = PocketBaseSyncClient(
      baseUrl: 'http://localhost:8090',
      settings: InMemoryAppSettingsRepository(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pocketBaseSyncClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Register'), findsWidgets);
    expect(find.text('Log in'), findsWidgets);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('shows a plain error in the UI when login fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_FailingLoginAccountNotifier.new),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to "Log in" mode (the form defaults to Register), then
    // submit.
    await tester.tap(find.text('Log in').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'me@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrong-password');
    await tester.tap(find.text('Log in').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Could not log in. Check your email and password.'),
      findsOneWidget,
    );
  });

  testWidgets('logged-in mode shows the email and a log out action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountProvider.overrideWith(_LoggedInAccountNotifier.new)],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Logged in as me@example.com'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `flutter test test/widget/account_screen_test.dart`
Expected: FAIL — `AccountScreen` not defined.

- [ ] **Step 4: Implement**

```dart
// lib/features/account/widgets/account_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/account/account_providers.dart';

/// Lets a guest register a new account or log into an existing one; once
/// logged in, shows the account's email and a way to log out. See spec:
/// account-based sync replaces the pairing-code identity model.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegisterMode = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    try {
      if (_isRegisterMode) {
        await ref.read(accountProvider.notifier).register(email, password);
      } else {
        await ref.read(accountProvider.notifier).login(email, password);
      }
    } catch (_) {
      setState(
        () => _error = _isRegisterMode
            ? 'Could not register. That email may already be in use.'
            : 'Could not log in. Check your email and password.',
      );
    }
  }

  Future<void> _logout() async {
    await ref.read(accountProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: account.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _buildForm(context),
          data: (email) =>
              email != null ? _buildLoggedIn(email) : _buildForm(context),
        ),
      ),
    );
  }

  Widget _buildLoggedIn(String email) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Logged in as $email'),
      const SizedBox(height: 24),
      ElevatedButton(onPressed: _logout, child: const Text('Log out')),
    ],
  );

  Widget _buildForm(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Register')),
          ButtonSegment(value: false, label: Text('Log in')),
        ],
        selected: {_isRegisterMode},
        onSelectionChanged: (selected) =>
            setState(() => _isRegisterMode = selected.first),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _emailController,
        decoration: const InputDecoration(labelText: 'Email'),
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _passwordController,
        decoration: const InputDecoration(labelText: 'Password'),
        obscureText: true,
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: _submit,
        child: Text(_isRegisterMode ? 'Register' : 'Log in'),
      ),
      if (_error != null) ...[
        const SizedBox(height: 16),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `flutter test test/widget/account_screen_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/account/widgets/account_screen.dart test/widget/account_screen_test.dart lib/features/pairing/widgets/pairing_screen.dart test/widget/pairing_screen_test.dart
git commit -m "feat: add AccountScreen (register/login/logout), replacing PairingScreen"
```

---

### Task 7: Wire into the app (`app_shell.dart`, `router.dart`, `main.dart`)

**Files:**
- Modify: `lib/core/widgets/app_shell.dart`
- Modify: `lib/router.dart`
- Modify: `lib/main.dart`
- Modify: `test/widget/app_shell_test.dart`

**Interfaces:**
- Consumes: `AccountScreen` (Task 6), `accountLogoutProvider`/`pocketBaseSyncClientProvider` (Task 5), `logout()` (Task 4), `PocketBaseSyncClient` (Task 3).

- [ ] **Step 1: Rename the nav-shell entry**

In `lib/core/widgets/app_shell.dart`, rename `_SyncDevicesEntry` to `_AccountEntry`, update its doc comment, label, and route:

```dart
/// Entry point for the `/account` screen, listed at the bottom of the
/// nav drawer/sidebar (the only way to reach it — it's a top-level route
/// outside the branch shell, so it isn't one of [_destinations]).
class _AccountEntry extends StatelessWidget {
  const _AccountEntry({required this.isNarrow});

  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.account_circle),
      title: const Text('Account'),
      onTap: () {
        if (isNarrow) Navigator.pop(context);
        context.push('/account');
      },
    );
  }
}
```

Update every call site in the same file that references `_SyncDevicesEntry` (e.g. `_SyncDevicesEntry(isNarrow: ...)` in the drawer/sidebar build methods) to `_AccountEntry(isNarrow: ...)`.

- [ ] **Step 2: Update the route**

In `lib/router.dart`, change the import from `package:taskframe/features/pairing/widgets/pairing_screen.dart` to `package:taskframe/features/account/widgets/account_screen.dart`, and the route:

```dart
GoRoute(
  path: '/account',
  builder: (context, state) => const AccountScreen(),
),
```

- [ ] **Step 3: Wire `accountLogoutProvider` into `main.dart`**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/app.dart';
import 'package:taskframe/core/platform/persistent_storage.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/storage/first_run_seed.dart';
import 'package:taskframe/core/storage/sembast_overrides.dart';
import 'package:taskframe/core/sync/account_service.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_engine.dart';
import 'package:taskframe/core/sync/sync_trigger.dart';
import 'package:taskframe/features/account/account_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();
  await seedIfEmpty(db);
  await requestPersistentStorage();

  final appSettings = SembastAppSettingsRepository(db);
  final syncClient = PocketBaseSyncClient(
    baseUrl: pocketBaseBaseUrl,
    settings: appSettings,
  );
  final syncEngine = SyncEngine(
    db: db,
    settings: appSettings,
    backend: syncClient,
  );
  // Restore (and, if needed, refresh) any previously-authenticated
  // session before the first sync trigger fires, so an already-logged-in
  // device doesn't spuriously throw/skip its first sync of this session.
  // A genuinely unauthenticated (guest) device still legitimately
  // fails-and-retries here - it has nothing to sync to yet.
  await syncClient.restoreSession();
  startSyncTriggers(engine: syncEngine);

  runApp(
    ProviderScope(
      overrides: [
        ...sembastOverrides(db),
        pocketBaseSyncClientProvider.overrideWithValue(syncClient),
        accountLogoutProvider.overrideWithValue(
          () => logout(db: db, settings: appSettings, client: syncClient),
        ),
      ],
      child: const App(),
    ),
  );
}
```

- [ ] **Step 4: Update the widget test**

In `test/widget/app_shell_test.dart`: change the test router's `path: '/pairing'` route to `path: '/account'` (keep its stub builder returning e.g. `const Text('Account screen')` instead of `const Text('Pairing screen')`), and update the two navigation tests' text/expectations from `'Sync devices'`/`'pairing'` wording to `'Account'`/`'account'` (`find.text('Sync devices')` → `find.text('Account')`; the route assertions and test descriptions naming "pairing" → "account").

- [ ] **Step 5: Run the full suite**

Run: `export PATH="$PATH:/home/alex/flutter/bin" && dart format . && flutter analyze && dart run custom_lint && flutter test test/unit test/widget`
Expected: all clean, all green. (`test/integration` is not run here — it needs Task 1's live schema migration to already be applied, which Task 6 of this plan re-verifies end to end.)

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/app_shell.dart lib/router.dart lib/main.dart test/widget/app_shell_test.dart
git commit -m "feat: wire AccountScreen into the app shell, router, and composition root"
```

---

### Task 8: Retarget integration tests to register/login; add merge and logout scenarios

**Files:**
- Modify: `test/integration/pocketbase_sync_test.dart`

**Interfaces:**
- Consumes: `PocketBaseSyncClient.register`/`.login` (Task 3), `logout()` (Task 4), `syncCollections`/`SyncEngine` (existing, unchanged). Requires Task 1's live PocketBase schema migration to already be applied in this environment.

- [ ] **Step 1: Replace pairing calls with register/login in the three existing scenarios**

In each of the three existing tests, replace:

```dart
final code = await deviceAClient.createGroup();
await deviceBClient.joinGroup(code);
```

with a unique-per-test email (so re-running the suite without a full PocketBase reset doesn't collide on a previously-used email — unlike the old pairing codes, which were single-use group creations, a `register` a second time to the same address is a real conflict), e.g. for the first test:

```dart
final email = 'edit-propagation-${DateTime.now().microsecondsSinceEpoch}@test.local';
await deviceAClient.register(email, 'testpass123');
await deviceBClient.login(email, 'testpass123');
```

Apply the same pattern (a distinct, timestamp-suffixed email per test) to the "delete propagates" and "concurrent edits" tests.

- [ ] **Step 2: Add a register-uploads-guest-data scenario**

```dart
// test/integration/pocketbase_sync_test.dart — add inside the existing group
test('registering uploads data created while in guest mode', () async {
  await tasksStore.record('guest1').put(deviceADb, {
    'id': 'guest1',
    'title': 'Created as a guest',
    'closed': false,
    'categoryId': '0',
    'tags': <String>[],
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'deleted': false,
  });

  // Guest mode: syncing before any account exists is a no-op (throws,
  // swallowed by SyncEngine, retried later) - the record stays local.
  await deviceAEngine.syncAll([_tasksCollection]);

  final email =
      'guest-register-${DateTime.now().microsecondsSinceEpoch}@test.local';
  await deviceAClient.register(email, 'testpass123');
  await deviceAEngine.syncAll([_tasksCollection]);
  await deviceBClient.login(email, 'testpass123');
  await deviceBEngine.syncAll([_tasksCollection]);

  final onB = await tasksStore.record('guest1').get(deviceBDb);
  expect(onB!['title'], 'Created as a guest');
});
```

- [ ] **Step 3: Add a login-to-existing-account-merges scenario**

```dart
// test/integration/pocketbase_sync_test.dart — add inside the existing group
test(
  'logging into an existing account merges local guest data with the '
  "account's existing data",
  () async {
    final email =
        'merge-${DateTime.now().microsecondsSinceEpoch}@test.local';

    // Device A registers and syncs one record - this account now has
    // remote data.
    await deviceAClient.register(email, 'testpass123');
    await tasksStore.record('fromA').put(deviceADb, {
      'id': 'fromA',
      'title': 'From device A',
      'closed': false,
      'categoryId': '0',
      'tags': <String>[],
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'deleted': false,
    });
    await deviceAEngine.syncAll([_tasksCollection]);

    // Device B has its own local guest record, then logs into the same
    // (already-populated) account.
    await tasksStore.record('fromBGuest').put(deviceBDb, {
      'id': 'fromBGuest',
      'title': 'From device B, created as a guest',
      'closed': false,
      'categoryId': '0',
      'tags': <String>[],
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'deleted': false,
    });
    await deviceBClient.login(email, 'testpass123');
    await deviceBEngine.syncAll([_tasksCollection]);

    // Device B should now have both records.
    expect((await tasksStore.record('fromA').get(deviceBDb))!['title'], 'From device A');
    expect(
      (await tasksStore.record('fromBGuest').get(deviceBDb))!['title'],
      'From device B, created as a guest',
    );

    // And device A, after another sync, should see device B's guest
    // record too.
    await deviceAEngine.syncAll([_tasksCollection]);
    expect(
      (await tasksStore.record('fromBGuest').get(deviceADb))!['title'],
      'From device B, created as a guest',
    );
  },
);
```

- [ ] **Step 4: Add a logout scenario**

```dart
// test/integration/pocketbase_sync_test.dart — add inside the existing group, needs the account_service import
test('logout clears local data and a later login re-pulls it', () async {
  final email =
      'logout-${DateTime.now().microsecondsSinceEpoch}@test.local';
  await deviceAClient.register(email, 'testpass123');
  await tasksStore.record('persisted').put(deviceADb, {
    'id': 'persisted',
    'title': 'Should survive logout on the server',
    'closed': false,
    'categoryId': '0',
    'tags': <String>[],
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'deleted': false,
  });
  await deviceAEngine.syncAll([_tasksCollection]);

  await logout(db: deviceADb, settings: deviceASettings, client: deviceAClient);

  expect(await tasksStore.record('persisted').get(deviceADb), isNull);

  await deviceAClient.login(email, 'testpass123');
  await deviceAEngine.syncAll([_tasksCollection]);

  final onA = await tasksStore.record('persisted').get(deviceADb);
  expect(onA!['title'], 'Should survive logout on the server');
});
```

Add the needed import at the top of the file: `import 'package:taskframe/core/sync/account_service.dart';`

- [ ] **Step 5: Run against a freshly-reset live PocketBase**

Run: `docker compose down -v && docker compose up -d --build pocketbase`
Run: `docker compose exec pocketbase /pb/pocketbase superuser upsert dev@taskframe.local dev-password-change-me`
Run: `dart run scripts/setup_pocketbase.dart http://localhost:8090 dev@taskframe.local dev-password-change-me`
Run: `make integration-test`
Expected: all 6 tests pass (3 retargeted + 3 new).

- [ ] **Step 6: Commit**

```bash
git add test/integration/pocketbase_sync_test.dart
git commit -m "test: retarget integration tests to register/login, add merge and logout scenarios"
```

---

## Self-Review Notes

- **Spec coverage:** `users` collection replaces `sync_groups`/`owner` replaces `sync_group` (Task 1), guest mode requires no new code and is confirmed by the register-uploads-guest-data integration scenario (Task 8), no-separate-migration-step (Tasks 5/8, epoch-cursor behavior reused as-is from the existing `SyncEngine`), logout wipes local data/cursors/session but not unrelated settings or server data (Tasks 4/8), auth screen replacing the pairing screen with the nav entry relabeled "Account" (Tasks 6-7), error handling matching the existing pairing screen's plain-text-error pattern (Task 6), minimal auth scope with no email verification/password reset (no task adds either) — all covered.
- **Placeholder scan:** Task 5's `build()` snippet's missing `await` is flagged explicitly inline as something for the executor to add, not left ambiguous.
- **Type consistency:** `logout({required Database db, required AppSettingsRepository settings, required PocketBaseSyncClient client})` is used identically in Task 4's implementation, Task 5's `main.dart` wiring closure, and Task 8's new integration test. `AccountNotifier`'s state type (`String?`, the email) is consistent between Task 5's definition and Task 6's `AccountScreen`/test fakes (`_FailingLoginAccountNotifier`, `_LoggedInAccountNotifier`).
