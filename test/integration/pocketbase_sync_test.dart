// test/integration/pocketbase_sync_test.dart
//
// Requires a local PocketBase with collections already set up — see
// `make integration-test`. Skipped by `make check`/`make test`, which
// only run test/unit and test/widget.
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

void main() {
  group('PocketBase sync (requires a local server)', () {
    late Database deviceADb;
    late Database deviceBDb;
    late AppSettingsRepository deviceASettings;
    late AppSettingsRepository deviceBSettings;
    late PocketBaseSyncClient deviceAClient;
    late PocketBaseSyncClient deviceBClient;
    late SyncEngine deviceAEngine;
    late SyncEngine deviceBEngine;

    setUp(() async {
      deviceADb = await newDatabaseFactoryMemory().openDatabase('a.db');
      deviceBDb = await newDatabaseFactoryMemory().openDatabase('b.db');
      deviceASettings = InMemoryAppSettingsRepository();
      deviceBSettings = InMemoryAppSettingsRepository();
      deviceAClient = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: deviceASettings,
      );
      deviceBClient = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: deviceBSettings,
      );
      deviceAEngine = SyncEngine(
        db: deviceADb,
        settings: deviceASettings,
        backend: deviceAClient,
      );
      deviceBEngine = SyncEngine(
        db: deviceBDb,
        settings: deviceBSettings,
        backend: deviceBClient,
      );
    });

    test('an edit on device A appears on device B after pairing', () async {
      final code = await deviceAClient.createGroup();
      await deviceBClient.joinGroup(code);

      await tasksStore.record('t1').put(deviceADb, {
        'id': 't1',
        'title': 'Buy milk',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });

      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      final onB = await tasksStore.record('t1').get(deviceBDb);
      expect(onB!['title'], 'Buy milk');
    });

    test('a delete on device A propagates to device B', () async {
      final code = await deviceAClient.createGroup();
      await deviceBClient.joinGroup(code);

      await tasksStore.record('t2').put(deviceADb, {
        'id': 't2',
        'title': 'Temp',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });
      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      await tasksStore.record('t2').put(deviceADb, {
        'id': 't2',
        'title': 'Temp',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': true,
      });
      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      final onB = await tasksStore.record('t2').get(deviceBDb);
      expect(onB!['deleted'], isTrue);
    });

    test('concurrent edits resolve to the newer updatedAt', () async {
      final code = await deviceAClient.createGroup();
      await deviceBClient.joinGroup(code);

      final base = DateTime.now().toUtc();
      await tasksStore.record('t3').put(deviceADb, {
        'id': 't3',
        'title': 'From A',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': base.toIso8601String(),
        'deleted': false,
      });
      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      await tasksStore.record('t3').put(deviceADb, {
        'id': 't3',
        'title': 'Older edit from A',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': base.add(const Duration(seconds: 1)).toIso8601String(),
        'deleted': false,
      });
      await tasksStore.record('t3').put(deviceBDb, {
        'id': 't3',
        'title': 'Newer edit from B',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': base.add(const Duration(seconds: 5)).toIso8601String(),
        'deleted': false,
      });

      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);
      await deviceAEngine.syncAll([_tasksCollection]);

      final onA = await tasksStore.record('t3').get(deviceADb);
      expect(onA!['title'], 'Newer edit from B');
    });
  });
}

final _tasksCollection = SyncCollection(name: 'tasks', store: tasksStore);
