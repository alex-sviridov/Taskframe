import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

/// Handle returned by [startSyncTriggers], to stop triggering sync
/// (tests, or a future "sign out").
class SyncTriggerHandle {
  SyncTriggerHandle._(this._timer, this._connectivitySubscription);

  final Timer _timer;
  final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  void dispose() {
    _timer.cancel();
    _connectivitySubscription.cancel();
  }
}

/// Starts syncing [engine] against [syncCollections] on: right now (app
/// start), whenever connectivity is regained, and every 30 seconds while
/// the app is running. See spec: "Sync triggers: app start, connectivity
/// regained, and a foreground timer (~30s)."
SyncTriggerHandle startSyncTriggers({
  required SyncEngine engine,
  Connectivity? connectivity,
  Duration interval = const Duration(seconds: 30),
}) {
  final connectivityChecker = connectivity ?? Connectivity();

  unawaited(engine.syncAll(syncCollections));

  final timer = Timer.periodic(interval, (_) {
    unawaited(engine.syncAll(syncCollections));
  });

  final subscription = connectivityChecker.onConnectivityChanged.listen((
    results,
  ) {
    if (results.any((r) => r != ConnectivityResult.none)) {
      unawaited(engine.syncAll(syncCollections));
    }
  });

  return SyncTriggerHandle._(timer, subscription);
}
