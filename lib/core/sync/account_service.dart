import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

/// Wipes every synced sembast store and every push/pull sync cursor —
/// the storage-only half of "return to guest mode". Leaves unrelated
/// settings (e.g. the install-hint dismissal flag) and the session
/// (identity/token) untouched; callers are responsible for the session
/// side themselves, since [logout] and the "switching accounts" path in
/// `AccountNotifier` each need to sequence that differently around this
/// wipe.
Future<void> _wipeSyncedStores({
  required Database db,
  required AppSettingsRepository settings,
}) async {
  for (final collection in syncCollections) {
    await collection.store.delete(db);
    await settings.deleteValue('sync_push_${collection.name}');
    await settings.deleteValue('sync_pull_${collection.name}');
  }
  await remoteIdStore.delete(db);
}

/// Returns this device to a clean guest state: clears every synced
/// sembast store, every push/pull sync cursor, and the stored account
/// session — but leaves unrelated settings (e.g. the install-hint
/// dismissal flag) and the PocketBase account/server-side data
/// untouched. Logging back in re-pulls everything from the account.
///
/// First gives any not-yet-pushed local edit one last chance to reach
/// the server via a best-effort [SyncEngine.syncAll] — without this, an
/// edit made since the last sync trigger (e.g. moments before the user
/// hits "Log out", with no sync yet in flight to carry it) would be
/// silently discarded below with no server copy to fall back on. That
/// call runs and fully completes its own [SyncEngine.runExclusive]
/// section *before* this function's own begins — nesting one inside the
/// other would deadlock the mutex. If the device is offline, this flush
/// is a no-op (as with any sync attempt) and the edit is lost; there's
/// no way to push without a network.
///
/// The wipe itself runs exclusively of any in-flight or subsequent
/// [SyncEngine.syncAll] call via [SyncEngine.runExclusive], and clears
/// the session *first* (before wiping stores), so that:
///  - an already-in-flight sync's pull step can't write into a store this
///    call is about to wipe (it waits behind this call instead), and
///  - a sync that starts after this call begins immediately fails
///    `_requireOwner()` (no session) and retries later, rather than
///    running against a half-wiped device.
Future<void> logout({
  required Database db,
  required AppSettingsRepository settings,
  required PocketBaseSyncClient client,
  required SyncEngine syncEngine,
}) async {
  await syncEngine.syncAll(syncCollections);

  await syncEngine.runExclusive(() async {
    await client.clearSession();
    await _wipeSyncedStores(db: db, settings: settings);
  });
}

/// Authenticates as an existing account, then discards any local guest
/// data instead of merging it — the account's own data is pulled fresh
/// on the next sync. Unlike [logout], this does *not* flush pending
/// local edits first: guest data is being dropped, not preserved.
///
/// Authenticating and wiping both run inside one [SyncEngine.runExclusive]
/// section so a sync trigger (the 30s timer, connectivity regained) can't
/// slip in between them and push the guest data to the newly-authenticated
/// account before it's wiped.
Future<void> loginDroppingGuestData({
  required Database db,
  required AppSettingsRepository settings,
  required PocketBaseSyncClient client,
  required SyncEngine syncEngine,
  required String email,
  required String password,
}) {
  return syncEngine.runExclusive(() async {
    await client.login(email, password);
    await _wipeSyncedStores(db: db, settings: settings);
  });
}
