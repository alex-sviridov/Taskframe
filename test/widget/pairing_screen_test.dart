import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/features/pairing/pairing_providers.dart';
import 'package:taskframe/features/pairing/widgets/pairing_screen.dart';

/// A [PairingNotifier] whose [joinGroup] always fails, standing in for a
/// wrong pairing code without depending on a real PocketBase server -
/// keeps this a deterministic, network-free widget test. [build] is also
/// overridden so it never touches [pocketBaseSyncClientProvider] either.
class _FailingJoinPairingNotifier extends PairingNotifier {
  @override
  Future<bool> build() async => false;

  @override
  Future<void> joinGroup(String code) async {
    throw StateError('pairing code not found');
  }
}

void main() {
  testWidgets('shows create and join controls', (tester) async {
    final client = PocketBaseSyncClient(
      baseUrl: 'http://localhost:8090',
      settings: InMemoryAppSettingsRepository(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pocketBaseSyncClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: PairingScreen()),
      ),
    );

    expect(find.text('Create a new sync group'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
  });

  testWidgets('shows a plain error in the UI when the pairing code is wrong', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pairingProvider.overrideWith(_FailingJoinPairingNotifier.new),
        ],
        child: const MaterialApp(home: PairingScreen()),
      ),
    );

    await tester.enterText(find.byType(TextField), 'BADCOD');
    await tester.tap(find.text('Join with a code'));
    await tester.pumpAndSettle();

    expect(
      find.text("That code wasn't found. Check it and try again."),
      findsOneWidget,
    );
  });
}
