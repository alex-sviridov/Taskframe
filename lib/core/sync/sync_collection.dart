import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';

/// One synced sembast store, paired with the PocketBase collection name
/// it syncs against. [SyncEngine.syncAll] iterates a list of these.
class SyncCollection {
  const SyncCollection({required this.name, required this.store});

  /// The PocketBase collection name — also the key prefix for this
  /// collection's push/pull cursors.
  final String name;

  final StoreRef<String, Map<String, Object?>> store;
}

/// The six sembast stores synced by this app.
final List<SyncCollection> syncCollections = [
  SyncCollection(name: 'tasks', store: tasksStore),
  SyncCollection(name: 'categories', store: categoriesStore),
  SyncCollection(name: 'templates', store: templatesStore),
  SyncCollection(name: 'template_blocks', store: templateBlocksStore),
  SyncCollection(name: 'saved_searches', store: savedSearchesStore),
  SyncCollection(name: 'day_blocks', store: dayBlocksStore),
];
