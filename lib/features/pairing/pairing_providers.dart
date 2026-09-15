import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';

/// The PocketBase base URL. Overridden at the composition root
/// (`main.dart`) once a real deployment URL is known; defaults to the
/// local dev server started by `docker compose up pocketbase` (see
/// Task 1).
final pocketBaseBaseUrlProvider = Provider<String>(
  (ref) => 'http://localhost:8090',
);

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
