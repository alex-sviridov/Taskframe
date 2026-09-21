import 'package:web/web.dart' as web;

/// The page's resolved `<base href>` (e.g. `https://host/taskframe/`),
/// read at runtime rather than baked in at build time — nginx's entrypoint
/// script rewrites `<base href>` to match wherever the app is actually
/// served (see `Dockerfile`/`docker-entrypoint.sh`) so this keeps API
/// calls same-prefix as the app under a subpath deployment, without
/// requiring a rebuild.
String defaultPocketBaseBaseUrl() => web.document.baseURI;
