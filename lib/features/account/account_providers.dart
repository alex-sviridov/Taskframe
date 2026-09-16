// lib/features/account/account_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';

/// The PocketBase base URL. Defaults to `/` (same-origin) — nginx
/// (`nginx.conf`) proxies `/api/` to the `pocketbase` service, so the web
/// app never needs to know PocketBase's real host. Override at build time
/// with `--dart-define=POCKETBASE_URL=...` for a deployment where the app
/// isn't served through that proxy (e.g. a native build talking to a
/// PocketBase host directly).
const pocketBaseBaseUrl = String.fromEnvironment(
  'POCKETBASE_URL',
  defaultValue: '/',
);

/// Riverpod-accessible form of [pocketBaseBaseUrl], for widgets/tests.
final pocketBaseBaseUrlProvider = Provider<String>((ref) => pocketBaseBaseUrl);

final pocketBaseSyncClientProvider = Provider<PocketBaseSyncClient>((ref) {
  throw UnimplementedError(
    'Override with a PocketBaseSyncClient built from appSettingsRepositoryProvider '
    'at the composition root — see sembastOverrides in main.dart.',
  );
});

/// Runs the full "return to guest mode" flow (`logout()` in
/// `account_service.dart`, which needs the raw [Database] this provider
/// doesn't have direct access to). Overridden at the composition root,
/// where that database is available — see `main.dart`.
final accountLogoutProvider = Provider<Future<void> Function()>((ref) {
  throw UnimplementedError(
    'Override with a closure calling logout(...) at the composition root '
    '— see main.dart.',
  );
});

/// This device's account state: the logged-in email, or `null` for guest
/// mode. Also exposes the actions to register/log in/log out.
class AccountNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final client = ref.watch(pocketBaseSyncClientProvider);
    final restored = await client.restoreSession();
    return restored ? await client.currentEmail() : null;
  }

  /// Registers a new account, uploading any local guest data to it on
  /// the next sync (no separate migration step — see the design doc).
  Future<void> register(String email, String password) async {
    await ref.read(pocketBaseSyncClientProvider).register(email, password);
    state = AsyncData(email);
  }

  /// Logs into an existing account, merging local guest data into it on
  /// the next sync.
  Future<void> login(String email, String password) async {
    await ref.read(pocketBaseSyncClientProvider).login(email, password);
    state = AsyncData(email);
  }

  /// Returns to guest mode: clears local synced data/cursors/session.
  Future<void> logout() async {
    await ref.read(accountLogoutProvider)();
    state = const AsyncData(null);
  }
}

final accountProvider = AsyncNotifierProvider<AccountNotifier, String?>(
  AccountNotifier.new,
);
