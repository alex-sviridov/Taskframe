// test/widget/account_screen_test.dart
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
  Future<String?> build() async => null;

  @override
  Future<void> login(String email, String password) async {
    throw StateError('invalid credentials');
  }
}

/// An [AccountNotifier] that reports an already-logged-in state, for
/// testing the logged-in view without a real session.
class _LoggedInAccountNotifier extends AccountNotifier {
  @override
  Future<String?> build() async => 'me@example.com';

  @override
  Future<void> logout() async {
    state = const AsyncData(null);
  }
}

void main() {
  testWidgets('guest mode shows register/login form controls', (
    tester,
  ) async {
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

  testWidgets('shows a plain error in the UI when login fails', (
    tester,
  ) async {
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
}
