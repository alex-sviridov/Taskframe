import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';

/// One synced sembast store, paired with the PocketBase collection name
/// it syncs against. `SyncEngine.syncAll` iterates a list of these.
class SyncCollection {
  /// Creates a [SyncCollection].
  const new({required this.name, required this.store});

  /// The PocketBase collection name — also the key prefix for this
  /// collection's push/pull cursors.
  final String name;

  /// The local sembast store this collection syncs.
  final StoreRef<String, Map<String, Object?>> store;
}

/// Maps `"<collectionName>:<entityId>"` to `{'id': <PocketBase record
/// id>}`. `SyncEngine` uses this to push straight to `update(id, ...)`
/// instead of asking PocketBase whether a record already exists (a
/// network round trip per push) — see `SyncBackend.upsert`.
///
/// Kept as its own store, separate from each collection's own domain
/// store, because every domain repository writes with a plain
/// (non-merging) `put` — keeping this bookkeeping on the domain record
/// itself would make an unrelated field edit silently erase it.
final StoreRef<String, Map<String, Object?>> remoteIdStore =
    stringMapStoreFactory.store('sync_remote_ids');

/// The [remoteIdStore] key for [entityId] in [collectionName].
String remoteIdKey(String collectionName, String entityId) =>
    '$collectionName:$entityId';

/// The six sembast stores synced by this app.
final List<SyncCollection> syncCollections = [
  SyncCollection(name: 'tasks', store: tasksStore),
  SyncCollection(name: 'categories', store: categoriesStore),
  SyncCollection(name: 'templates', store: templatesStore),
  SyncCollection(name: 'template_blocks', store: templateBlocksStore),
  SyncCollection(name: 'saved_searches', store: savedSearchesStore),
  SyncCollection(name: 'day_blocks', store: dayBlocksStore),
];
