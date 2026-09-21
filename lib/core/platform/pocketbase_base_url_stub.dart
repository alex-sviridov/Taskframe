/// Off web, there's no page `<base href>` to derive a same-origin default
/// from — callers are expected to override via `--dart-define`.
String defaultPocketBaseBaseUrl() => '/';
