import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Asks the browser to mark this origin's storage as "persistent" — a
/// best-effort hint that reduces (but does not guarantee) the odds of
/// iOS Safari evicting IndexedDB data under storage pressure. Never
/// throws: an unsupported or denied request is not an error worth
/// surfacing, since the app already works without it.
Future<void> requestPersistentStorage() async {
  try {
    await web.window.navigator.storage.persist().toDart;
  } on Object catch (_) {
    // Best-effort only.
  }
}
