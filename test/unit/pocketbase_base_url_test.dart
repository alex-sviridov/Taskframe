// test/unit/pocketbase_base_url_test.dart
//
// Covers `resolvePocketBaseBaseUrl`, which decides the PocketBase client's
// base URL: an explicit `--dart-define=POCKETBASE_URL=...` override always
// wins; otherwise it falls back to a platform-supplied default (on web,
// derived from the page's actual `<base href>` at runtime, so API calls
// stay same-prefix as the app when served from a subpath — see
// `account_providers.dart`).
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/account/account_providers.dart';

void main() {
  test('uses the explicit override when one is provided', () {
    final url = resolvePocketBaseBaseUrl(
      override: 'http://example.com:8090',
      defaultUrl: () =>
          fail('should not consult the default when override is set'),
    );

    expect(url, 'http://example.com:8090');
  });

  test('falls back to the platform default when no override is provided', () {
    final url = resolvePocketBaseBaseUrl(
      override: '',
      defaultUrl: () => '/taskframe/',
    );

    expect(url, '/taskframe/');
  });
}
