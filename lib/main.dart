import 'dart:async';

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
  // Restores (and, if needed, refreshes) any previously-authenticated
  // session, so an already-logged-in device's syncs succeed instead of
  // failing `_requireOwner()` until the account screen happens to be
  // opened. Deliberately NOT awaited: the local-first UI below doesn't
  // need this to render, and this app must still start promptly while
  // fully offline (no timeout on a real network call would otherwise
  // block `runApp` — see PocketBaseSyncClient's own bounded timeout).
  // A sync attempt that races ahead of this finishing just fails
  // `_requireOwner()` harmlessly and retries on the next trigger (30s
  // timer, connectivity regained, or the sync right after this call
  // resolves below).
  unawaited(syncClient.restoreSession());

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
