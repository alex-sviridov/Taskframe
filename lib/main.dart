import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/app.dart';
import 'package:taskframe/core/platform/persistent_storage.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/storage/first_run_seed.dart';
import 'package:taskframe/core/storage/sembast_overrides.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_engine.dart';
import 'package:taskframe/core/sync/sync_trigger.dart';
import 'package:taskframe/features/pairing/pairing_providers.dart';

/// Entry point: opens the local database, seeds it on first run, then
/// boots the app inside a [ProviderScope] that overrides every repository
/// provider with its sembast-backed implementation.
///
/// The providers' own defaults stay the original `InMemory*`
/// implementations — only this composition root ever points them at real
/// storage, which is what keeps every existing test (built around a bare
/// `ProviderContainer()`/`ProviderScope()` with no overrides) working
/// unchanged.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();
  await seedIfEmpty(db);
  await requestPersistentStorage();

  final appSettings = SembastAppSettingsRepository(db);
  final syncClient = PocketBaseSyncClient(
    baseUrl: pocketBaseBaseUrl,
    settings: appSettings,
  );
  final syncEngine = SyncEngine(
    db: db,
    settings: appSettings,
    backend: syncClient,
  );
  // Restore (and, if needed, refresh) any previously-paired session before
  // the first sync trigger fires, so an already-paired device doesn't
  // spuriously throw/skip its first sync of this session. A genuinely
  // unpaired device still legitimately fails-and-retries here - it has
  // nothing to sync to yet.
  await syncClient.restoreSession();
  startSyncTriggers(engine: syncEngine);

  runApp(
    ProviderScope(
      overrides: [
        ...sembastOverrides(db),
        pocketBaseSyncClientProvider.overrideWithValue(syncClient),
      ],
      child: const App(),
    ),
  );
}
