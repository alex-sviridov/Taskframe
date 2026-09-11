import 'package:web/web.dart' as web;

/// Whether the page is currently running in the browser's "standalone"
/// display mode — true once a PWA has been added to the home screen and
/// launched from there, false for a normal browser tab.
bool isStandaloneDisplayMode() =>
    web.window.matchMedia('(display-mode: standalone)').matches;
