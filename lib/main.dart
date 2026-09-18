import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/app.dart';
import 'package:taskframe/core/platform/persistent_storage.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/storage/first_run_seed.dart';
import 'package:taskframe/core/storage/sembast_overrides.dart';
import 'package:taskframe/core/sync/account_service.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_engine.dart';
import 'package:taskframe/core/sync/sync_trigger.dart';
import 'package:taskframe/features/account/account_providers.dart';

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
  // Restore (and, if needed, refresh) any previously-authenticated
  // session before the first sync trigger fires, so an already-logged-in
  // device doesn't spuriously throw/skip its first sync of this session.
  // A genuinely unauthenticated (guest) device still legitimately
  // fails-and-retries here - it has nothing to sync to yet.
  await syncClient.restoreSession();

  // Built explicitly (rather than letting ProviderScope create one
  // implicitly) so startSyncTriggers' onSynced callback below can reach
  // it directly — a background sync pull writes straight to sembast
  // with no other route back into the widget tree's provider state, so
  // this is what makes new server data show up without a manual reload.
  final container = ProviderContainer(
    overrides: [
      ...sembastOverrides(db),
      pocketBaseSyncClientProvider.overrideWithValue(syncClient),
      accountLogoutProvider.overrideWithValue(
        () => logout(
          db: db,
          settings: appSettings,
          client: syncClient,
          syncEngine: syncEngine,
        ),
      ),
    ],
  );

  startSyncTriggers(
    engine: syncEngine,
    onSynced: (changedCollections) {
      for (final name in changedCollections) {
        final provider = syncedProvidersByCollection[name];
        if (provider != null) container.invalidate(provider);
      }
    },
  );

  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
