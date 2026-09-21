// test/widget/account_screen_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/features/account/account_providers.dart';
import 'package:taskframe/features/account/widgets/account_screen.dart';

/// An [AccountNotifier] whose [login] always fails, standing in for
/// wrong credentials without depending on a real PocketBase server —
/// keeps this a deterministic, network-free widget test. [build] is
/// also overridden so it never touches [pocketBaseSyncClientProvider].
class _FailingLoginAccountNotifier extends AccountNotifier {
  @override
  Future<AccountState> build() async => const AccountState(email: null);

  @override
  Future<void> login(String email, String password) async {
    throw StateError('invalid credentials');
  }
}

/// An [AccountNotifier] that reports an already-logged-in state, for
/// testing the logged-in view without a real session.
class _LoggedInAccountNotifier extends AccountNotifier {
  @override
  Future<AccountState> build() async =>
      const AccountState(email: 'me@example.com');

  @override
  Future<void> logout() async {
    state = const AsyncData(AccountState(email: null));
  }
}

/// An [AccountNotifier] reporting a session PocketBase rejected as
/// expired — the UI must prompt for re-authentication rather than
/// showing a plain "logged in" view that would leave sync silently
/// broken forever.
class _ExpiredSessionAccountNotifier extends AccountNotifier {
  @override
  Future<AccountState> build() async =>
      const AccountState(email: 'me@example.com', sessionExpired: true);

  int loginCalls = 0;

  @override
  Future<void> login(String email, String password) async {
    loginCalls++;
    state = const AsyncData(AccountState(email: 'me@example.com'));
  }
}

/// An [AccountNotifier] whose [register] hangs until a gate completes,
/// counting how many times it's invoked — used to prove the submit
/// button guards against a fast double-tap firing two concurrent
/// registrations.
class _SlowRegisterAccountNotifier extends AccountNotifier {
  new(this._gate);

  final Completer<void> _gate;
  int registerCalls = 0;

  @override
  Future<AccountState> build() async => const AccountState(email: null);

  @override
  Future<void> register(String email, String password) async {
    registerCalls++;
    await _gate.future;
    state = const AsyncData(AccountState(email: 'new@example.com'));
  }
}

void main() {
  testWidgets('guest mode shows register/login form controls', (tester) async {
    final client = PocketBaseSyncClient(
      baseUrl: 'http://localhost:8090',
      settings: InMemoryAppSettingsRepository(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pocketBaseSyncClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Register'), findsWidgets);
    expect(find.text('Log in'), findsWidgets);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('shows a plain error in the UI when login fails', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_FailingLoginAccountNotifier.new),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to "Log in" mode (the form defaults to Register), then
    // submit.
    await tester.tap(find.text('Log in').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'me@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrong-password');
    await tester.tap(find.text('Log in').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Could not log in. Check your email and password.'),
      findsOneWidget,
    );
  });

  testWidgets('logged-in mode shows the email and a log out action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountProvider.overrideWith(_LoggedInAccountNotifier.new)],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Logged in as me@example.com'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets(
    'expired session prompts for the password instead of showing a plain '
    'logged-in view',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWith(_ExpiredSessionAccountNotifier.new),
          ],
          child: const MaterialApp(home: AccountScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('expired'), findsOneWidget);
      expect(find.textContaining('me@example.com'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // password only
      expect(find.text('Log in again'), findsOneWidget);
      // Not the plain logged-in view, which would hide that sync is dead.
      expect(find.text('Logged in as me@example.com'), findsNothing);

      await tester.enterText(find.byType(TextField), 'correct-password');
      await tester.tap(find.text('Log in again'));
      await tester.pumpAndSettle();

      final notifier = ProviderScope.containerOf(
        tester.element(find.byType(AccountScreen)),
      ).read(accountProvider.notifier) as _ExpiredSessionAccountNotifier;
      expect(notifier.loginCalls, 1);
    },
  );

  testWidgets('submit button is disabled while a registration is in flight, '
      'preventing a double-tap from firing two calls', (tester) async {
    final gate = Completer<void>();
    late _SlowRegisterAccountNotifier notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(
            () => notifier = _SlowRegisterAccountNotifier(gate),
          ),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'new@example.com');
    await tester.enterText(find.byType(TextField).last, 'testpass123');

    // First tap starts the (gated) registration.
    await tester.tap(find.text('Register').last);
    await tester.pump();
    await tester.pump();

    // The button must now be disabled — a real second tap on a
    // disabled ElevatedButton is a no-op at the framework level, so
    // this alone proves the guard.
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Register'),
    );
    expect(button.onPressed, isNull);

    // Attempting the tap again must not fire another call.
    await tester.tap(find.text('Register').last, warnIfMissed: false);
    await tester.pump();

    expect(notifier.registerCalls, 1);

    gate.complete();
    await tester.pumpAndSettle();
  });
}
