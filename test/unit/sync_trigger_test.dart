import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/sync_engine.dart';
import 'package:taskframe/core/sync/sync_trigger.dart';

/// Lets tests drive [Connectivity.onConnectivityChanged] without a real
/// platform channel — see the connectivity_plus testing docs: swap
/// `ConnectivityPlatform.instance` for a fake that extends it, then use
/// the real (singleton) [Connectivity] as normal.
class _FakeConnectivityPlatform extends ConnectivityPlatform {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  void emit(List<ConnectivityResult> results) => _controller.add(results);

  Future<void> dispose() => _controller.close();
}

/// A [SyncBackend] that just counts how many times `syncAll` actually
/// reached it, so tests can assert on trigger *count* without caring
/// about push/pull mechanics (already covered by sync_engine_test.dart).
class _CountingBackend implements SyncBackend {
  int upsertCalls = 0;
  int listCalls = 0;

  /// When true, [listChangedSince] returns one remote record that wins
  /// LWW against local (which has nothing for this id), so `syncAll`
  /// reports the collection as changed — lets tests exercise
  /// [startSyncTriggers]'s `onSynced` callback without needing
  /// sync_engine.dart's own push/pull mechanics (covered elsewhere).
  bool hasRemoteChange = false;

  @override
  Future<void> upsert(String collection, Map<String, Object?> record) async {
    upsertCalls++;
  }

  @override
  Future<List<Map<String, Object?>>> listChangedSince(
    String collection,
    DateTime cursor,
  ) async {
    listCalls++;
    if (!hasRemoteChange) return [];
    final now = DateTime.now().toUtc().toIso8601String();
    return [
      {
        'entity_id': 'a',
        'updated_at': now,
        'server_updated': now,
        'deleted': false,
        'data': {'id': 'a', 'updatedAt': now, 'deleted': false},
      },
    ];
  }
}

void main() {
  late Database db;
  late _FakeConnectivityPlatform fakePlatform;
  late _CountingBackend backend;
  late SyncEngine engine;

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('test.db');
    fakePlatform = _FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fakePlatform;
    backend = _CountingBackend();
    engine = SyncEngine(
      db: db,
      settings: InMemoryAppSettingsRepository(),
      backend: backend,
    );
  });

  tearDown(() async {
    await fakePlatform.dispose();
  });

  test('fires immediately on start', () async {
    final handle = startSyncTriggers(
      engine: engine,
      connectivity: Connectivity(),
      interval: const Duration(minutes: 10),
    );
    addTearDown(handle.dispose);

    // syncAll is fired-and-forgotten (unawaited); let it complete.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.listCalls, greaterThan(0));
  });

  test('fires periodically via the timer', () {
    fakeAsync((async) {
      final handle = startSyncTriggers(
        engine: engine,
        connectivity: Connectivity(),
        // Explicit even though it matches startSyncTriggers' own
        // default - this test is specifically about the periodic
        // interval, so spelling it out here is intentional.
        // ignore: avoid_redundant_argument_values
        interval: const Duration(seconds: 30),
      );
      addTearDown(handle.dispose);
      async.flushMicrotasks();

      final afterStart = backend.listCalls;
      expect(afterStart, greaterThan(0));

      async.elapse(const Duration(seconds: 30));
      expect(backend.listCalls, greaterThan(afterStart));

      final afterOneTick = backend.listCalls;
      async.elapse(const Duration(seconds: 30));
      expect(backend.listCalls, greaterThan(afterOneTick));
    });
  });

  test('fires when connectivity is regained', () async {
    final handle = startSyncTriggers(
      engine: engine,
      connectivity: Connectivity(),
      interval: const Duration(minutes: 10),
    );
    addTearDown(handle.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final beforeRegained = backend.listCalls;
    fakePlatform.emit([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.listCalls, greaterThan(beforeRegained));
  });

  test('does not fire when connectivity is lost (goes to none)', () async {
    final handle = startSyncTriggers(
      engine: engine,
      connectivity: Connectivity(),
      interval: const Duration(minutes: 10),
    );
    addTearDown(handle.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final beforeLost = backend.listCalls;
    fakePlatform.emit([ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.listCalls, beforeLost);
  });

  test('calls onSynced with the changed-collection names after a sync that '
      'actually applied a remote change', () async {
    backend.hasRemoteChange = true;
    Set<String>? received;
    final handle = startSyncTriggers(
      engine: engine,
      connectivity: Connectivity(),
      interval: const Duration(minutes: 10),
      onSynced: (changed) => received = changed,
    );
    addTearDown(handle.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(received, isNotNull);
    expect(received, isNotEmpty);
  });

  test('calls onSynced with an empty set when nothing changed', () async {
    Set<String>? received;
    final handle = startSyncTriggers(
      engine: engine,
      connectivity: Connectivity(),
      interval: const Duration(minutes: 10),
      onSynced: (changed) => received = changed,
    );
    addTearDown(handle.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(received, isEmpty);
  });

  test('dispose stops both the timer and the connectivity subscription', () {
    fakeAsync((async) {
      final handle = startSyncTriggers(
        engine: engine,
        connectivity: Connectivity(),
        // Explicit even though it matches startSyncTriggers' own
        // default - this test is specifically about the periodic
        // interval, so spelling it out here is intentional.
        // ignore: avoid_redundant_argument_values
        interval: const Duration(seconds: 30),
      );
      async.flushMicrotasks();

      handle.dispose();
      final afterDispose = backend.listCalls;

      async.elapse(const Duration(seconds: 60));
      fakePlatform.emit([ConnectivityResult.wifi]);
      async.flushMicrotasks();

      expect(backend.listCalls, afterDispose);
    });
  });
}
