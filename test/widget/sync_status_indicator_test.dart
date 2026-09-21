// test/widget/sync_status_indicator_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/sync/sync_status.dart';
import 'package:taskframe/core/widgets/sync_status_indicator.dart';
import 'package:taskframe/features/account/account_providers.dart';

/// An [AccountNotifier] that resolves to a fixed [AccountState], for
/// driving [SyncStatusIndicator] without a real PocketBase client.
class _FixedAccountNotifier extends AccountNotifier {
  new(this._state);

  final AccountState _state;

  @override
  Future<AccountState> build() async => _state;
}

/// A [SyncStatusNotifier] that resolves to a fixed [SyncStatus].
class _FixedSyncStatusNotifier extends SyncStatusNotifier {
  new(this._status);

  final SyncStatus _status;

  @override
  SyncStatus build() => _status;
}

Future<void> _pump(
  WidgetTester tester, {
  required AccountState account,
  SyncStatus status = SyncStatus.idle,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountProvider.overrideWith(() => _FixedAccountNotifier(account)),
        syncStatusProvider.overrideWith(() => _FixedSyncStatusNotifier(status)),
      ],
      child: const MaterialApp(home: Scaffold(body: SyncStatusIndicator())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows "Local only" in guest mode, regardless of sync status', (
    tester,
  ) async {
    await _pump(
      tester,
      account: const AccountState(email: null),
      status: SyncStatus.error,
    );

    expect(find.textContaining('Local only'), findsOneWidget);
  });

  testWidgets('shows "Synced" when logged in and the last attempt was clean', (
    tester,
  ) async {
    await _pump(tester, account: const AccountState(email: 'me@example.com'));

    expect(find.textContaining('Synced'), findsOneWidget);
  });

  testWidgets('shows "Syncing" while a sync attempt is in flight', (
    tester,
  ) async {
    await _pump(
      tester,
      account: const AccountState(email: 'me@example.com'),
      status: SyncStatus.syncing,
    );

    expect(find.textContaining('Syncing'), findsOneWidget);
  });

  testWidgets('shows a sync issue when the last attempt failed', (
    tester,
  ) async {
    await _pump(
      tester,
      account: const AccountState(email: 'me@example.com'),
      status: SyncStatus.error,
    );

    expect(find.textContaining('Sync issue'), findsOneWidget);
  });

  testWidgets('shows a sync issue when the session expired, even if the '
      'last raw sync status was idle', (tester) async {
    await _pump(
      tester,
      account: const AccountState(
        email: 'me@example.com',
        sessionExpired: true,
      ),
    );

    expect(find.textContaining('Sync issue'), findsOneWidget);
  });
}
