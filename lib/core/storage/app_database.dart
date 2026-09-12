import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/database_factory.dart';

/// Day blocks, keyed by block id, each record carrying a `dateKey` field
/// (see `date_key.dart`) that `load` filters on.
final StoreRef<String, Map<String, Object?>> dayBlocksStore =
    stringMapStoreFactory.store('day_blocks');

/// Categories, keyed by category id, each record carrying an `order`
/// field that preserves creation order (with the default category
/// seeded at order 0, so it always sorts first).
final StoreRef<String, Map<String, Object?>> categoriesStore =
    stringMapStoreFactory.store('categories');

/// Templates, keyed by template id, each record carrying an `order`
/// field that preserves creation order.
final StoreRef<String, Map<String, Object?>> templatesStore =
    stringMapStoreFactory.store('templates');

/// Template blocks, keyed by block id, each record carrying a
/// `templateId` field that `load`/`deleteAll` filter on.
final StoreRef<String, Map<String, Object?>> templateBlocksStore =
    stringMapStoreFactory.store('template_blocks');

/// Small app settings (currently just install-hint dismissal), keyed by
/// setting name.
final StoreRef<String, Map<String, Object?>> settingsStore =
    stringMapStoreFactory.store('settings');

/// Opens the app's single sembast [Database], using the platform-correct
/// factory and location from `database_factory.dart`.
Future<Database> openAppDatabase() async {
  final factory = createDatabaseFactory();
  final path = await databasePath();
  return await factory.openDatabase(path);
}
