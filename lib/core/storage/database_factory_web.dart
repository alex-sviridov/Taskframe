import 'package:sembast_web/sembast_web.dart';

/// The web, IndexedDB-backed sembast factory.
DatabaseFactory createDatabaseFactory() => databaseFactoryWeb;

/// The app's database name on web — sembast_web keys IndexedDB databases
/// by name rather than filesystem path, so no directory is involved.
Future<String> databasePath() async => 'taskframe.db';
