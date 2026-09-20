// test/unit/pocketbase_sync_client_test.dart
//
// Covers the network-free parts of PocketBaseSyncClient that don't need a
// live PocketBase (that's test/integration/pocketbase_sync_test.dart):
// specifically, that a hung network call doesn't block the app forever —
// see the offline-startup fix in main.dart, which this backs.
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';

/// An [http.Client] whose every request hangs forever — stands in for a
/// connection to an unreachable/black-holed network.
class _HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _neverCompletes<http.StreamedResponse>();

  @override
  void close() {}
}

Future<T> _neverCompletes<T>() => Completer<T>().future;

/// A syntactically-valid (unsigned) JWT with the given expiry, matching
/// what PocketBase's `AuthStore.isValid` expects to parse — just enough
/// for `restoreSession()` to treat the stored token as worth refreshing.
String _fakeJwt({required DateTime expiry}) {
  String encode(Map<String, Object?> obj) =>
      base64Url.encode(utf8.encode(jsonEncode(obj))).replaceAll('=', '');
  final header = encode({'alg': 'none', 'typ': 'JWT'});
  final payload = encode({'exp': expiry.millisecondsSinceEpoch ~/ 1000});
  return '$header.$payload.sig';
}

void main() {
  test('restoreSession() gives up and returns false instead of hanging '
      'forever when the network never responds', () {
    fakeAsync((async) {
      final settings = InMemoryAppSettingsRepository();
      unawaited(
        settings.setValue(
          'account_token',
          _fakeJwt(expiry: DateTime.now().add(const Duration(days: 1))),
        ),
      );
      async.flushMicrotasks();

      final client = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: settings,
        httpClientFactory: _HangingClient.new,
      );

      bool? result;
      unawaited(client.restoreSession().then((r) => result = r));

      async.elapse(const Duration(minutes: 1));

      expect(result, isFalse);
    });
  });
}
