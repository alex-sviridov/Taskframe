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
