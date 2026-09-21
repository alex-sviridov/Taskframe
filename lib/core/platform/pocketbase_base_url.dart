/// The default PocketBase base URL for this platform, used when no
/// explicit `--dart-define=POCKETBASE_URL=...` override is given.
library;

export 'pocketbase_base_url_stub.dart'
    if (dart.library.js_interop) 'pocketbase_base_url_web.dart';
