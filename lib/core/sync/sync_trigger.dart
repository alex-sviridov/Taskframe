import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

/// Handle returned by [startSyncTriggers], to stop triggering sync
/// (tests, or a future "sign out").
class SyncTriggerHandle {
  /// Creates a [SyncTriggerHandle] owning [_timer] and
  /// [_connectivitySubscription].
  new(this._timer, this._connectivitySubscription);

  final Timer _timer;
  final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  /// Stops both the periodic timer and the connectivity subscription.
  void dispose() {
    _timer.cancel();
    // dispose() isn't async and has nothing to wait for; cancellation
    // completing is not something a caller needs to observe here.
    unawaited(_connectivitySubscription.cancel());
  }
}

/// Starts syncing [engine] against [syncCollections] on: right now (app
/// start), whenever connectivity is regained, and every 30 seconds while
/// the app is running. See spec: "Sync triggers: app start, connectivity
/// regained, and a foreground timer (~30s)."
///
/// [onSynced], when given, is called after every sync attempt with the
/// set of collection names [SyncEngine.syncAll] actually applied a
/// remote change to — a background pull writes straight to local
/// storage with no other way to tell the app's already-running UI state
/// that new data arrived, so a composition root wires this to
/// invalidate the matching providers.
SyncTriggerHandle startSyncTriggers({
  required SyncEngine engine,
  Connectivity? connectivity,
  Duration interval = const Duration(seconds: 30),
  void Function(Set<String> changedCollections)? onSynced,
}) {
  final connectivityChecker = connectivity ?? Connectivity();

  Future<void> sync() async {
    final changed = await engine.syncAll(syncCollections);
    onSynced?.call(changed);
  }

  unawaited(sync());

  final timer = Timer.periodic(interval, (_) {
    unawaited(sync());
  });

  // Cancelled in SyncTriggerHandle.dispose(), not here — the lint can't
  // see that this subscription is handed off to the returned handle.
  // ignore: cancel_subscriptions
  final subscription = connectivityChecker.onConnectivityChanged.listen((
    results,
  ) {
    if (results.any((r) => r != ConnectivityResult.none)) {
      unawaited(sync());
    }
  });

  return SyncTriggerHandle(timer, subscription);
}
