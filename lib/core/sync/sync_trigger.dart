import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

/// Handle returned by [startSyncTriggers], to stop triggering sync
/// (tests, or a future "sign out").
class SyncTriggerHandle {
  /// Creates a [SyncTriggerHandle] that runs [_disposeAll] to tear
  /// everything down.
  new(this._disposeAll);

  final void Function() _disposeAll;

  /// Stops the periodic timer and every subscription driving it.
  void dispose() => _disposeAll();
}

/// A [Stream] of `true` (app visible/foregrounded) and `false` (hidden/
/// backgrounded) events, built from [WidgetsBinding]'s lifecycle
/// notifications — covers a browser tab being hidden/shown as well as a
/// mobile app being backgrounded/foregrounded, with no platform-specific
/// code of its own.
///
/// [AppLifecycleListener] fires more than one callback for a single
/// visible/hidden transition (e.g. both `onShow` and `onResume` on
/// foregrounding), each of which would otherwise map to its own `true`/
/// `false` event here. `.distinct()` collapses consecutive repeats so a
/// single resume triggers exactly one downstream sync, not two.
Stream<bool> _defaultVisibilityChanges() {
  late final AppLifecycleListener listener;
  final controller = StreamController<bool>(onCancel: () => listener.dispose());
  listener = AppLifecycleListener(
    onShow: () => controller.add(true),
    onResume: () => controller.add(true),
    onHide: () => controller.add(false),
    onPause: () => controller.add(false),
  );
  return controller.stream.distinct();
}

/// Starts syncing [engine] against [syncCollections] on: right now (app
/// start), whenever connectivity is regained, every 30 seconds while the
/// app is running and visible, and immediately upon becoming visible
/// again after being hidden. See spec: "Sync triggers: app start,
/// connectivity regained, and a foreground timer (~30s)." The timer is
/// paused while hidden/backgrounded — a hidden browser tab or
/// backgrounded app has nothing to show a pull's result to, so ticking it
/// only spends network/battery for no visible benefit.
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
  Stream<bool>? visibilityChanges,
  Duration interval = const Duration(seconds: 30),
  void Function(Set<String> changedCollections)? onSynced,
}) {
  final connectivityChecker = connectivity ?? Connectivity();
  final visibility = visibilityChanges ?? _defaultVisibilityChanges();

  Future<void> sync() async {
    final changed = await engine.syncAll(syncCollections);
    onSynced?.call(changed);
  }

  Timer? timer;
  void startTimer() {
    timer ??= Timer.periodic(interval, (_) => unawaited(sync()));
  }

  void stopTimer() {
    timer?.cancel();
    timer = null;
  }

  unawaited(sync());
  startTimer();

  final connectivitySubscription = connectivityChecker.onConnectivityChanged
      .listen((results) {
        if (results.any((r) => r != ConnectivityResult.none)) {
          unawaited(sync());
        }
      });

  final visibilitySubscription = visibility.listen((visible) {
    if (visible) {
      unawaited(sync());
      startTimer();
    } else {
      stopTimer();
    }
  });

  return SyncTriggerHandle(() {
    stopTimer();
    unawaited(connectivitySubscription.cancel());
    unawaited(visibilitySubscription.cancel());
  });
}
