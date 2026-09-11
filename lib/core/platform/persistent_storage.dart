/// Requests persistent storage from the browser, on platforms that
/// support it. A no-op everywhere else.
export 'persistent_storage_stub.dart'
    if (dart.library.html) 'persistent_storage_web.dart';
