import 'package:flutter_test/flutter_test.dart';
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

  /// When true, [listChangedSince] throws instead of returning — simulates
  /// a pull failing (e.g. a network blip or a dead session).
  bool failListChangedSince = false;

  /// Every `remoteId` [upsert] was called with, in call order — `null`
  /// means "no known remote id yet" (a first-ever push of that entity).
  /// Lets tests assert a push never re-derives a remote id it was
  /// already given, instead of just asserting on the end state.
  final List<String?> remoteIdsSeen = [];

  var _nextId = 1;

  @override
  Future<String> upsert(
    String collection,
    Map<String, Object?> record, {
    String? remoteId,
  }) async {
    remoteIdsSeen.add(remoteId);
    if (failUpsertFor.contains(record['entity_id'])) {
      throw StateError('simulated upsert failure for ${record['entity_id']}');
    }
    final list = remote.putIfAbsent(collection, () => []);
    final index = list.indexWhere((r) => r['entity_id'] == record['entity_id']);
    final id = remoteId ?? 'remote-${_nextId++}';
    final stored = {...record, 'remote_id': id};
    if (index == -1) {
      list.add(stored);
    } else {
      list[index] = stored;
    }
    return id;
  }

  @override
  Future<List<Map<String, Object?>>> listChangedSince(
    String collection,
    DateTime cursor,
  ) async {
    if (failListChangedSince) {
      throw StateError('simulated listChangedSince failure');
    }
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
        'updatedAt': DateTime.utc(2026).toIso8601String(),
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
        'updatedAt': DateTime.utc(2026).toIso8601String(),
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
        'updatedAt': DateTime.utc(2026).toIso8601String(),
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
          'updated_at': DateTime.utc(2026).toIso8601String(),
          'server_updated': DateTime.utc(2026).toIso8601String(),
          'deleted': false,
          'data': {
            'id': 'a',
            'title': 'old-remote',
            'updatedAt': DateTime.utc(2026).toIso8601String(),
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
      final tied = DateTime.utc(2026);
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
      'updatedAt': DateTime.utc(2026).toIso8601String(),
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
          'updated_at': DateTime.utc(2026).toIso8601String(),
          'server_updated': DateTime.utc(2026).toIso8601String(),
          'deleted': false,
          'data': {
            'id': 'a',
            'title': 'remote-edit',
            'updatedAt': DateTime.utc(2026).toIso8601String(),
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

  test('syncAll returns the collection name when a remote record was '
      'actually applied locally (remote wins)', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'title': 'old',
      'updatedAt': DateTime.utc(2026).toIso8601String(),
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

    final outcome = await engine.syncAll([things]);

    expect(outcome.changed, {'things'});
  });

  test('syncAll returns an empty set when a remote record loses LWW '
      '(nothing actually changed locally)', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'title': 'new-local',
      'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
      'deleted': false,
    });
    backend.remote['things'] = [
      {
        'entity_id': 'a',
        'updated_at': DateTime.utc(2026).toIso8601String(),
        'server_updated': DateTime.utc(2026).toIso8601String(),
        'deleted': false,
        'data': {
          'id': 'a',
          'title': 'old-remote',
          'updatedAt': DateTime.utc(2026).toIso8601String(),
          'deleted': false,
        },
      },
    ];

    final outcome = await engine.syncAll([things]);

    expect(outcome.changed, isEmpty);
  });

  test('syncAll returns an empty set when there is nothing to pull', () async {
    final outcome = await engine.syncAll([things]);

    expect(outcome.changed, isEmpty);
  });

  test('syncAll only reports collections that actually had a change applied, '
      'not every collection synced', () async {
    final otherStore = stringMapStoreFactory.store('others');
    final others = SyncCollection(name: 'others', store: otherStore);

    backend.remote['things'] = [
      {
        'entity_id': 'a',
        'updated_at': DateTime.utc(2026).toIso8601String(),
        'server_updated': DateTime.utc(2026).toIso8601String(),
        'deleted': false,
        'data': {
          'id': 'a',
          'title': 'from-remote',
          'updatedAt': DateTime.utc(2026).toIso8601String(),
          'deleted': false,
        },
      },
    ];
    // 'others' has nothing on the remote at all.

    final outcome = await engine.syncAll([things, others]);

    expect(outcome.changed, {'things'});
  });

  test('syncAll reports hadError: false when every collection syncs '
      'cleanly', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'updatedAt': DateTime.utc(2026).toIso8601String(),
      'deleted': false,
    });

    final outcome = await engine.syncAll([things]);

    expect(outcome.hadError, isFalse);
  });

  test('syncAll reports hadError: true when a record fails to push', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'updatedAt': DateTime.utc(2026).toIso8601String(),
      'deleted': false,
    });
    backend.failUpsertFor = {'a'};

    final outcome = await engine.syncAll([things]);

    expect(outcome.hadError, isTrue);
  });

  test('syncAll reports hadError: true when a pull fails', () async {
    backend.failListChangedSince = true;

    final outcome = await engine.syncAll([things]);

    expect(outcome.hadError, isTrue);
  });

  test(
    'cursor advancement on partial-failure push: only succeeded records '
    'advance the push cursor, the failing one is retried next time',
    () async {
      await store.record('a').put(db, {
        'id': 'a',
        'title': 'first',
        'updatedAt': DateTime.utc(2026).toIso8601String(),
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
        DateTime.utc(2026).toIso8601String(),
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

  test('a first-ever push has no known remote id, and a later push of the '
      'same entity reuses the id the backend assigned it — never asking '
      'the backend whether the record already exists', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'title': 'first',
      'updatedAt': DateTime.utc(2026).toIso8601String(),
      'deleted': false,
    });
    await engine.syncAll([things]);
    final assignedId = backend.remote['things']!.single['remote_id'];

    await store.record('a').put(db, {
      'id': 'a',
      'title': 'second',
      'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
      'deleted': false,
    });
    await engine.syncAll([things]);

    expect(backend.remoteIdsSeen, [null, assignedId]);
  });

  test('the remote id survives a non-merging write to the domain record made '
      'in between two syncs (as every real repository write does)', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'title': 'first',
      'updatedAt': DateTime.utc(2026).toIso8601String(),
      'deleted': false,
    });
    await engine.syncAll([things]);
    final assignedId = backend.remote['things']!.single['remote_id'];

    // A plain (non-merge) put, as a domain repository's update() does —
    // this must not be able to erase sync's own remote-id bookkeeping,
    // since that bookkeeping isn't kept on the domain record itself.
    await store.record('a').put(db, {
      'id': 'a',
      'title': 'second',
      'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
      'deleted': false,
    });
    await engine.syncAll([things]);

    expect(backend.remoteIdsSeen.last, assignedId);
  });

  test('a record pulled from the remote learns its remote id locally too, so '
      'a later local edit updates that record instead of creating a '
      'duplicate', () async {
    backend.remote['things'] = [
      {
        'entity_id': 'a',
        'remote_id': 'existing-remote-id',
        'updated_at': DateTime.utc(2026).toIso8601String(),
        'server_updated': DateTime.utc(2026).toIso8601String(),
        'deleted': false,
        'data': {
          'id': 'a',
          'title': 'from-remote',
          'updatedAt': DateTime.utc(2026).toIso8601String(),
          'deleted': false,
        },
      },
    ];
    await engine.syncAll([things]);

    await store.record('a').put(db, {
      'id': 'a',
      'title': 'edited-locally',
      'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
      'deleted': false,
    });
    await engine.syncAll([things]);

    expect(backend.remoteIdsSeen, contains('existing-remote-id'));
    expect(backend.remote['things'], hasLength(1));
  });

  test('a record pulled but losing LWW (local stays newer) still learns its '
      'remote id, so the not-yet-pushed local edit updates it rather than '
      'creating a duplicate', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'title': 'newer-local',
      'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
      'deleted': false,
    });
    backend.remote['things'] = [
      {
        'entity_id': 'a',
        'remote_id': 'existing-remote-id',
        'updated_at': DateTime.utc(2026).toIso8601String(),
        'server_updated': DateTime.utc(2026).toIso8601String(),
        'deleted': false,
        'data': {
          'id': 'a',
          'title': 'older-remote',
          'updatedAt': DateTime.utc(2026).toIso8601String(),
          'deleted': false,
        },
      },
    ];

    await engine.syncAll([things]);

    expect(backend.remoteIdsSeen, ['existing-remote-id']);
  });

  test('the local remote-id bookkeeping is never sent as part of the pushed '
      'record itself', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'updatedAt': DateTime.utc(2026).toIso8601String(),
      'deleted': false,
    });
    await engine.syncAll([things]);

    await store.record('a').put(db, {
      'id': 'a',
      'title': 'second',
      'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
      'deleted': false,
    });
    await engine.syncAll([things]);

    final pushed = backend.remote['things']!.single;
    expect(pushed.containsKey('_pbId'), isFalse);
  });
}
