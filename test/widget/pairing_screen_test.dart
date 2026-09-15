import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/features/pairing/pairing_providers.dart';
import 'package:taskframe/features/pairing/widgets/pairing_screen.dart';

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
}
