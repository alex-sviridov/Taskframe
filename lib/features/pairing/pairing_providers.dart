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

/// Whether this device currently belongs to a sync group (has a stored
/// pairing session), and the actions to create/join one.
class PairingNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.watch(pocketBaseSyncClientProvider).restoreSession();

  Future<String> createGroup() async {
    final code = await ref.read(pocketBaseSyncClientProvider).createGroup();
    state = const AsyncData(true);
    return code;
  }

  Future<void> joinGroup(String code) async {
    await ref.read(pocketBaseSyncClientProvider).joinGroup(code);
    state = const AsyncData(true);
  }
}

final pairingProvider = AsyncNotifierProvider<PairingNotifier, bool>(
  PairingNotifier.new,
);
