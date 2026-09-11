import 'package:web/web.dart' as web;

/// `navigator.standalone` is a non-standard, Safari-only boolean (`true`
/// when launched from the home screen) that predates the standard
/// `display-mode` media feature. `package:web`'s [web.Navigator] binding
/// only covers standard WebIDL, so it isn't exposed there — this adds it
/// via a JS interop extension instead of a raw property lookup, so it
/// stays type-checked like the rest of the interop surface.
extension on web.Navigator {
  external bool? get standalone;
}

/// Whether the page is currently running in the browser's "standalone"
/// display mode — true once a PWA has been added to the home screen and
/// launched from there, false for a normal browser tab.
///
/// Checks both signals rather than only the standard `display-mode`
/// media feature: iOS Safari's support for that media feature has been
/// inconsistent in practice, while `navigator.standalone` has been the
/// authoritative iOS-specific signal since iOS 1.1.3. Every other
/// browser leaves `navigator.standalone` `undefined`, so this only ever
/// adds a true positive, never a false one.
bool isStandaloneDisplayMode() =>
    web.window.matchMedia('(display-mode: standalone)').matches ||
    (web.window.navigator.standalone ?? false);
