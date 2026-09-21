// test/unit/pocketbase_sync_client_test.dart
//
// Covers the network-free parts of PocketBaseSyncClient that don't need a
// live PocketBase (that's test/integration/pocketbase_sync_test.dart):
// - that a hung network call doesn't block the app forever — see the
//   offline-startup fix in main.dart, which this backs.
// - that restoreSession() distinguishes "couldn't verify, treat as still
//   logged in" (offline/timeout) from "server rejected the token" (a
//   genuinely dead session that needs a fresh login) — see AccountNotifier,
//   which surfaces the latter as `sessionExpired` so the UI can prompt for
//   re-authentication instead of letting sync fail silently forever.
// - that concurrent restoreSession() calls (main.dart's startup call and
//   AccountNotifier.build()'s can overlap) share one network request.
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

/// An [http.Client] that responds to every request with a fixed status
/// code and JSON body, for simulating a specific PocketBase API response
/// without a live server.
class _FixedResponseClient extends http.BaseClient {
  new({required this.statusCode});

  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), statusCode);
  }

  @override
  void close() {}
}

/// An [http.Client] whose every `send()` call is routed through a single
/// shared callback — lets a test resolve every concurrent caller with
/// one response and count how many requests were actually made, proving
/// they shared a single in-flight request instead of each firing their
/// own.
class _SharedResponseClient extends http.BaseClient {
  new(this._onSend);

  final Future<http.StreamedResponse> Function() _onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _onSend();

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

http.StreamedResponse _authRefreshOkResponse(String newToken) =>
    http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'token': newToken,
            'record': {'id': 'user123'},
          }),
        ),
      ),
      200,
    );

void main() {
  test('restoreSession() gives up and returns offline instead of hanging '
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

      SessionRestoreResult? result;
      unawaited(client.restoreSession().then((r) => result = r));

      async.elapse(const Duration(minutes: 1));

      expect(result, SessionRestoreResult.offline);
    });
  });

  test('restoreSession() returns expired when the server rejects the '
      'stored token (not just a network failure)', () async {
    final settings = InMemoryAppSettingsRepository();
    await settings.setValue(
      'account_token',
      _fakeJwt(expiry: DateTime.now().add(const Duration(days: 1))),
    );

    final client = PocketBaseSyncClient(
      baseUrl: 'http://localhost:8090',
      settings: settings,
      httpClientFactory: () => _FixedResponseClient(statusCode: 401),
    );

    final result = await client.restoreSession();

    expect(result, SessionRestoreResult.expired);
  });

  test('restoreSession() returns noSession when nothing is stored', () async {
    final client = PocketBaseSyncClient(
      baseUrl: 'http://localhost:8090',
      settings: InMemoryAppSettingsRepository(),
    );

    final result = await client.restoreSession();

    expect(result, SessionRestoreResult.noSession);
  });

  test(
    'concurrent restoreSession() calls share a single network request',
    () async {
      final settings = InMemoryAppSettingsRepository();
      await settings.setValue(
        'account_token',
        _fakeJwt(expiry: DateTime.now().add(const Duration(days: 1))),
      );

      var sendCount = 0;
      final responseCompleter = Completer<http.StreamedResponse>();
      Future<http.StreamedResponse> onSend() {
        sendCount++;
        return responseCompleter.future;
      }

      final client = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: settings,
        httpClientFactory: () => _SharedResponseClient(onSend),
      );

      final first = client.restoreSession();
      final second = client.restoreSession();

      // Let both calls actually start (and reach the network layer) before
      // resolving the one shared response.
      await Future<void>.delayed(Duration.zero);
      responseCompleter.complete(_authRefreshOkResponse('new-token'));

      final results = await Future.wait([first, second]);

      expect(sendCount, 1);
      expect(results, [
        SessionRestoreResult.restored,
        SessionRestoreResult.restored,
      ]);
    },
  );
}
