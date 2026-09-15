import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

/// A [SyncBackend] backed by an in-memory map, standing in for
/// PocketBase in these tests.
class FakeSyncBackend implements SyncBackend {
  final Map<String, List<Map<String, Object?>>> remote = {};

  @override
  Future<void> upsert(String collection, Map<String, Object?> record) async {
    final list = remote.putIfAbsent(collection, () => []);
    final index = list.indexWhere((r) => r['entity_id'] == record['entity_id']);
    if (index == -1) {
      list.add(record);
    } else {
      list[index] = record;
    }
  }

  @override
  Future<List<Map<String, Object?>>> listChangedSince(
    String collection,
    DateTime cursor,
  ) async {
    final list = remote[collection] ?? [];
    return [
      for (final record in list)
        if (DateTime.parse(record['updated_at']! as String).isAfter(cursor))
          record,
    ];
  }
}

void main() {
  late Database db;
  late InMemoryAppSettingsRepository settings;
  late FakeSyncBackend backend;
  late SyncEngine engine;

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('test.db');
    settings = InMemoryAppSettingsRepository();
    backend = FakeSyncBackend();
    engine = SyncEngine(db: db, settings: settings, backend: backend);
  });

  final store = stringMapStoreFactory.store('things');
  final things = SyncCollection(name: 'things', store: store);

  test(
    'pushes a locally-changed record and advances the push cursor',
    () async {
      await store.record('a').put(db, {
        'id': 'a',
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'deleted': false,
      });

      await engine.syncAll([things]);

      expect(backend.remote['things'], hasLength(1));
      expect(backend.remote['things']!.single['entity_id'], 'a');
      expect(await settings.getValue('sync_push_things'), isNotNull);
    },
  );

  test(
    'does not re-push a record already at or before the push cursor',
    () async {
      await store.record('a').put(db, {
        'id': 'a',
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'deleted': false,
      });
      await engine.syncAll([things]);
      backend.remote['things']!.clear();

      await engine.syncAll([things]);

      expect(backend.remote['things'], isEmpty);
    },
  );

  test(
    'pulls a remote record newer than the local copy (remote wins)',
    () async {
      await store.record('a').put(db, {
        'id': 'a',
        'title': 'old',
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'deleted': false,
      });
      backend.remote['things'] = [
        {
          'entity_id': 'a',
          'updated_at': DateTime.utc(2026, 1, 2).toIso8601String(),
          'deleted': false,
          'data': {
            'id': 'a',
            'title': 'new',
            'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
            'deleted': false,
          },
        },
      ];

      await engine.syncAll([things]);

      final local = await store.record('a').get(db);
      expect(local!['title'], 'new');
    },
  );

  test(
    'keeps the local record when it is newer than the remote copy',
    () async {
      await store.record('a').put(db, {
        'id': 'a',
        'title': 'new-local',
        'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
        'deleted': false,
      });
      backend.remote['things'] = [
        {
          'entity_id': 'a',
          'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
          'deleted': false,
          'data': {
            'id': 'a',
            'title': 'old-remote',
            'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
            'deleted': false,
          },
        },
      ];

      await engine.syncAll([things]);

      final local = await store.record('a').get(db);
      expect(local!['title'], 'new-local');
    },
  );

  test('a remote tombstone deletes the local record', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'title': 'still here',
      'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'deleted': false,
    });
    backend.remote['things'] = [
      {
        'entity_id': 'a',
        'updated_at': DateTime.utc(2026, 1, 2).toIso8601String(),
        'deleted': true,
        'data': {
          'id': 'a',
          'title': 'still here',
          'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
          'deleted': true,
        },
      },
    ];

    await engine.syncAll([things]);

    final local = await store.record('a').get(db);
    expect(local!['deleted'], isTrue);
  });
}
