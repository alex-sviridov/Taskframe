// test/unit/account_providers_test.dart
//
// Covers `AccountNotifier`'s account-switch wipe behavior (Important
// finding 4 in the final whole-branch review): authenticating as a
// *different* identity than whatever is currently stored must wipe the
// old identity's local data/cursors first, so it can't leak forward into
// the new session. Uses a fake [PocketBaseSyncClient] subclass whose
// `register`/`login` skip the real network call (they only need to
// change the stored identity for this test), so this stays a
// network-free unit test — real end-to-end cross-account behavior is
// covered by `test/integration/pocketbase_sync_test.dart` against a live
// PocketBase.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/features/account/account_providers.dart';

/// Stands in for the real network round-trip: just stores the new
/// identity, like the real `_authenticate` does, without calling out to
/// PocketBase.
class _FakePocketBaseSyncClient extends PocketBaseSyncClient {
  new({required super.settings}) : super(baseUrl: 'http://localhost:8090');

  @override
  Future<void> register(String email, String password) =>
      settings.setValue('account_identity', email);

  @override
  Future<void> login(String email, String password) =>
      settings.setValue('account_identity', email);

  @override
  Future<String?> currentEmail() => settings.getValue('account_identity');
}

void main() {
  test(
    'logging in as a different identity than the one currently stored '
    'wipes local synced data/cursors first (via accountLogoutProvider)',
    () async {
      final settings = InMemoryAppSettingsRepository();
      await settings.setValue('account_identity', 'old@example.com');
      final client = _FakePocketBaseSyncClient(settings: settings);

      var wipeCalls = 0;
      final container = ProviderContainer(
        overrides: [
          pocketBaseSyncClientProvider.overrideWithValue(client),
          accountLogoutProvider.overrideWithValue(() async {
            wipeCalls++;
            await settings.deleteValue('account_identity');
          }),
        ],
      );
      addTearDown(container.dispose);

      // Wait for build() to settle first.
      await container.read(accountProvider.future);

      await container
          .read(accountProvider.notifier)
          .login('new@example.com', 'testpass123');

      expect(wipeCalls, 1);
      expect(container.read(accountProvider).value, 'new@example.com');
    },
  );

  test('logging in as the SAME identity that is already stored does not '
      'wipe anything', () async {
    final settings = InMemoryAppSettingsRepository();
    await settings.setValue('account_identity', 'me@example.com');
    final client = _FakePocketBaseSyncClient(settings: settings);

    var wipeCalls = 0;
    final container = ProviderContainer(
      overrides: [
        pocketBaseSyncClientProvider.overrideWithValue(client),
        accountLogoutProvider.overrideWithValue(() async {
          wipeCalls++;
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountProvider.future);
    await container
        .read(accountProvider.notifier)
        .login('me@example.com', 'testpass123');

    expect(wipeCalls, 0);
  });

  test('registering from a clean guest state (no stored identity) does not '
      'wipe anything', () async {
    final settings = InMemoryAppSettingsRepository();
    final client = _FakePocketBaseSyncClient(settings: settings);

    var wipeCalls = 0;
    final container = ProviderContainer(
      overrides: [
        pocketBaseSyncClientProvider.overrideWithValue(client),
        accountLogoutProvider.overrideWithValue(() async {
          wipeCalls++;
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(accountProvider.future);
    await container
        .read(accountProvider.notifier)
        .register('brand-new@example.com', 'testpass123');

    expect(wipeCalls, 0);
    expect(container.read(accountProvider).value, 'brand-new@example.com');
  });
}
