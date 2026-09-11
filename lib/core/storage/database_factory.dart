/// Selects the platform-correct sembast [DatabaseFactory] and database
/// location: file-backed on native platforms, IndexedDB-backed on web.
export 'database_factory_stub.dart'
    if (dart.library.io) 'database_factory_io.dart'
    if (dart.library.js_interop) 'database_factory_web.dart';
