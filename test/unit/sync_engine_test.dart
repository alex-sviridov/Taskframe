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

  /// When set, [upsert] throws for any record whose `entity_id` is in
  /// this set instead of writing it — simulates a single record's push
  /// failing (e.g. a network blip) while the rest of the batch succeeds.
  Set<String> failUpsertFor = {};

  @override
  Future<void> upsert(String collection, Map<String, Object?> record) async {
    if (failUpsertFor.contains(record['entity_id'])) {
      throw StateError('simulated upsert failure for ${record['entity_id']}');
    }
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
        // Records written by a plain push() (as opposed to being set up
        // directly by a test via `backend.remote[...] = [...]`) don't
        // carry a `server_updated` - they're never surfaced back by pull,
        // same as a real PocketBase record wouldn't yet be visible to
        // this device via listChangedSince before it's actually written.
        if (record['server_updated'] != null &&
            DateTime.parse(record['server_updated']! as String).isAfter(cursor))
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
          'server_updated': DateTime.utc(2026, 1, 2).toIso8601String(),
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
          'server_updated': DateTime.utc(2026, 1, 1).toIso8601String(),
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

  test(
    'keeps the local record when remote and local timestamps are equal',
    () async {
      final tied = DateTime.utc(2026, 1, 1);
      await store.record('a').put(db, {
        'id': 'a',
        'title': 'local',
        'updatedAt': tied.toIso8601String(),
        'deleted': false,
      });
      backend.remote['things'] = [
        {
          'entity_id': 'a',
          'updated_at': tied.toIso8601String(),
          'server_updated': tied.toIso8601String(),
          'deleted': false,
          'data': {
            'id': 'a',
            'title': 'remote',
            'updatedAt': tied.toIso8601String(),
            'deleted': false,
          },
        },
      ];

      await engine.syncAll([things]);

      // isAfter (strict) means a tie does not overwrite the local copy.
      final local = await store.record('a').get(db);
      expect(local!['title'], 'local');
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
        'server_updated': DateTime.utc(2026, 1, 2).toIso8601String(),
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

  test(
    'a local tombstone wins over an older remote edit (deletion is pushed)',
    () async {
      await store.record('a').put(db, {
        'id': 'a',
        'title': 'edited-then-deleted',
        'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
        'deleted': true,
      });
      backend.remote['things'] = [
        {
          'entity_id': 'a',
          'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
          'server_updated': DateTime.utc(2026, 1, 1).toIso8601String(),
          'deleted': false,
          'data': {
            'id': 'a',
            'title': 'remote-edit',
            'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
            'deleted': false,
          },
        },
      ];

      await engine.syncAll([things]);

      // Pull: the local tombstone (newer) is kept, the older remote edit
      // is discarded.
      final local = await store.record('a').get(db);
      expect(local!['deleted'], isTrue);
      // Push: the local tombstone is then pushed to the remote.
      final pushed = backend.remote['things']!.singleWhere(
        (r) => r['entity_id'] == 'a',
      );
      expect(pushed['deleted'], isTrue);
    },
  );

  test(
    'cursor advancement on partial-failure push: only succeeded records '
    'advance the push cursor, the failing one is retried next time',
    () async {
      await store.record('a').put(db, {
        'id': 'a',
        'title': 'first',
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        'deleted': false,
      });
      await store.record('b').put(db, {
        'id': 'b',
        'title': 'second',
        'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
        'deleted': false,
      });
      backend.failUpsertFor = {'b'};

      await engine.syncAll([things]);

      // 'a' succeeded and was pushed; 'b' failed and was not.
      expect(backend.remote['things']!.map((r) => r['entity_id']), ['a']);
      // The push cursor only advanced past 'a', not 'b'.
      expect(
        await settings.getValue('sync_push_things'),
        DateTime.utc(2026, 1, 1).toIso8601String(),
      );

      // Retrying (failure lifted) picks up 'b', proving it was never
      // skipped by a cursor that over-advanced past it.
      backend.failUpsertFor = {};
      await engine.syncAll([things]);

      expect(backend.remote['things']!.map((r) => r['entity_id']).toSet(), {
        'a',
        'b',
      });
      expect(
        await settings.getValue('sync_push_things'),
        DateTime.utc(2026, 1, 2).toIso8601String(),
      );
    },
  );
}
