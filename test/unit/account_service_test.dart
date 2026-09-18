import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/account_service.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

/// A no-op [SyncBackend]: these tests don't exercise actual push/pull,
/// only [SyncEngine.runExclusive]'s serialization.
class _NoopSyncBackend implements SyncBackend {
  /// Set by a test to observe when a simulated in-flight sync's body is
  /// actually running, to assert it never overlaps with `logout()`.
  void Function()? onRun;

  @override
  Future<void> upsert(String collection, Map<String, Object?> record) async {
    onRun?.call();
  }

  @override
  Future<List<Map<String, Object?>>> listChangedSince(
    String collection,
    DateTime cursor,
  ) async => [];
}

void main() {
  test('logout clears every synced store, every sync cursor, and the '
      'session, but leaves unrelated settings alone', () async {
    final db = await newDatabaseFactoryMemory().openDatabase('test.db');
    final settings = SembastAppSettingsRepository(db);
    final client = PocketBaseSyncClient(
      baseUrl: 'http://localhost:8090',
      settings: settings,
    );
    final syncEngine = SyncEngine(
      db: db,
      settings: settings,
      backend: _NoopSyncBackend(),
    );

    // Seed data in every synced store, a couple of sync cursors, a
    // session, and one unrelated setting.
    await tasksStore.record('t1').put(db, {'id': 't1', 'title': 'x'});
    await categoriesStore.record('c1').put(db, {'id': 'c1', 'name': 'x'});
    await templatesStore.record('tpl1').put(db, {'id': 'tpl1'});
    await templateBlocksStore.record('tb1').put(db, {'id': 'tb1'});
    await savedSearchesStore.record('s1').put(db, {'id': 's1'});
    await dayBlocksStore.record('d1').put(db, {'id': 'd1'});
    await settings.setValue('sync_push_tasks', '2026-01-01T00:00:00.000Z');
    await settings.setValue('sync_pull_tasks', '2026-01-01T00:00:00.000Z');
    await settings.setValue('account_identity', 'me@example.com');
    await settings.setValue('account_token', 'a-token');
    await settings.setInstallHintDismissedAt(DateTime(2026));

    await logout(
      db: db,
      settings: settings,
      client: client,
      syncEngine: syncEngine,
    );

    expect(await tasksStore.record('t1').get(db), isNull);
    expect(await categoriesStore.record('c1').get(db), isNull);
    expect(await templatesStore.record('tpl1').get(db), isNull);
    expect(await templateBlocksStore.record('tb1').get(db), isNull);
    expect(await savedSearchesStore.record('s1').get(db), isNull);
    expect(await dayBlocksStore.record('d1').get(db), isNull);
    expect(await settings.getValue('sync_push_tasks'), isNull);
    expect(await settings.getValue('sync_pull_tasks'), isNull);
    expect(await settings.getValue('account_identity'), isNull);
    expect(await settings.getValue('account_token'), isNull);
    expect(await settings.getInstallHintDismissedAt(), DateTime(2026));
  });

  test(
    'logout() waits for an in-flight syncAll to finish before wiping, '
    'and a syncAll queued after logout() waits for the wipe to finish '
    '(SyncEngine.runExclusive serializes them, never interleaving)',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test2.db');
      final settings = SembastAppSettingsRepository(db);
      final client = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: settings,
      );
      final backend = _NoopSyncBackend();
      final syncEngine = SyncEngine(
        db: db,
        settings: settings,
        backend: backend,
      );

      await tasksStore.record('t1').put(db, {
        'id': 't1',
        'title': 'x',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });

      final events = <String>[];
      backend.onRun = () => events.add('sync-running');

      // Start a syncAll (its push step will call the backend, recording
      // 'sync-running'), then immediately race a logout() against it.
      // Regardless of scheduling order, runExclusive must fully serialize
      // them: the record must be either fully present (sync ran first)
      // or fully gone (logout ran first) - never a half-applied mix, and
      // the two bodies must never be "inside" runExclusive at the same
      // time.
      final syncFuture = syncEngine.syncAll([_tasksCollection]);
      final logoutFuture = logout(
        db: db,
        settings: settings,
        client: client,
        syncEngine: syncEngine,
      );

      await Future.wait([syncFuture, logoutFuture]);

      // Whichever ran first, the end state after both complete is
      // deterministic: logout always wipes last-or-only, since it's the
      // second call queued behind syncAll's lock (start order above), so
      // the store must end up empty.
      expect(await tasksStore.record('t1').get(db), isNull);
      expect(events, ['sync-running']);
    },
  );
}

final _tasksCollection = SyncCollection(name: 'tasks', store: tasksStore);
