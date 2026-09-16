import 'dart:async';

import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/sync_collection.dart';

/// What [SyncEngine] needs from a remote backend. [PocketBaseSyncClient]
/// (see `pocketbase_sync_client.dart`) is the real implementation; tests
/// use an in-memory fake.
abstract class SyncBackend {
  /// Creates or replaces the remote record whose `entity_id` is
  /// `record['id']`, in PocketBase collection [collection]. [record] is
  /// the full local sembast map for that entity (it must contain `id`,
  /// `updatedAt`, `deleted`).
  Future<void> upsert(String collection, Map<String, Object?> record);

  /// Returns every remote record in [collection] whose PocketBase-managed
  /// `server_updated` timestamp is strictly after [cursor]. Each returned
  /// map has `entity_id`, `updated_at` (the client-set last-write-wins
  /// timestamp), `server_updated` (PocketBase's own `updated` field, used
  /// only for cursor advancement — immune to client clock skew), `deleted`,
  /// and `data` (the original local sembast map as pushed by [upsert]).
  Future<List<Map<String, Object?>>> listChangedSince(
    String collection,
    DateTime cursor,
  );
}

/// Pushes locally-changed records and pulls remotely-changed records for
/// each [SyncCollection], resolving conflicts by comparing `updatedAt`
/// (last-write-wins). Never throws on a single collection's failure —
/// see [syncAll].
class SyncEngine {
  SyncEngine({
    required Database db,
    required AppSettingsRepository settings,
    required SyncBackend backend,
  }) : _db = db,
       _settings = settings,
       _backend = backend;

  final Database _db;
  final AppSettingsRepository _settings;
  final SyncBackend _backend;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Simple async mutex: chains work onto whatever's currently running so
  /// callers never interleave with each other. Guards against a sync in
  /// flight racing `logout()`'s store wipe (see [runExclusive]) and also
  /// serializes concurrent `syncAll` calls against each other (e.g. the
  /// manual "sync now" trigger and the 30s timer firing close together).
  ///
  /// `null` until first use, then lazily created on the first call to
  /// [runExclusive] — deliberately NOT eagerly initialized with
  /// `Future.value()` in this field's declaration, which would bind that
  /// initial Future to whatever zone happens to be active when the
  /// [SyncEngine] is constructed (e.g. a plain `setUp()`, outside any
  /// `fakeAsync` zone a test later runs the actual calls in). Creating it
  /// lazily, inside the first [runExclusive] call, ties it to the zone
  /// that's actually driving the async work.
  Future<void>? _lock;

  /// Runs [action] exclusively with respect to any other call to
  /// [runExclusive] (including [syncAll], which routes through this) on
  /// this [SyncEngine]: waits for anything currently running/queued, runs
  /// [action], then lets the next queued caller proceed. Errors from
  /// [action] don't poison the lock for subsequent callers.
  Future<T> runExclusive<T>(Future<T> Function() action) {
    final previous = _lock ?? Future.value();
    final completer = Completer<void>();
    _lock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  /// Runs pull then push for every collection in [collections], so a
  /// concurrently-newer remote change is absorbed locally before this
  /// device publishes its own changes (avoiding a stale local push
  /// clobbering a fresher remote record). A failure syncing one
  /// collection (e.g. a network error) is swallowed so the others still
  /// get a chance — matches the spec's "push/pull fail silently,
  /// retried on the next trigger". Runs exclusively of any other
  /// `syncAll`/[runExclusive] call on this engine (e.g. `logout()`'s
  /// store wipe), so a sync never races a concurrent operation that
  /// wipes the very stores it's reading/writing.
  Future<void> syncAll(List<SyncCollection> collections) {
    return runExclusive(() async {
      for (final collection in collections) {
        try {
          await _pull(collection);
        } on Object {
          // Best-effort; retried on the next trigger.
        }
        try {
          await _push(collection);
        } on Object {
          // Best-effort; retried on the next trigger.
        }
      }
    });
  }

  Future<void> _push(SyncCollection collection) async {
    final cursor = await _cursor('sync_push_${collection.name}');
    // Sorted ascending by updatedAt so a mid-batch failure (see below)
    // stops at a deterministic point: everything before it in time has
    // been confirmed pushed, everything from it onward is retried next
    // trigger - never skipping past a not-yet-pushed record.
    final finder = Finder(
      filter: Filter.greaterThan('updatedAt', cursor.toIso8601String()),
      sortOrders: [SortOrder('updatedAt')],
    );
    final records = await collection.store.find(_db, finder: finder);
    if (records.isEmpty) return;

    DateTime? maxSeen;
    for (final record in records) {
      final updatedAt = DateTime.parse(record.value['updatedAt']! as String);
      try {
        await _backend.upsert(collection.name, {
          ...record.value,
          'entity_id': record.key,
        });
      } on Object {
        // Stop here rather than propagating: everything up to this point
        // already succeeded and its cursor progress below must not be
        // lost. This record (and anything after it) is retried on the
        // next trigger.
        break;
      }
      if (maxSeen == null || updatedAt.isAfter(maxSeen)) maxSeen = updatedAt;
    }
    if (maxSeen != null) {
      await _settings.setValue(
        'sync_push_${collection.name}',
        maxSeen.toIso8601String(),
      );
    }
  }

  Future<void> _pull(SyncCollection collection) async {
    final cursor = await _cursor('sync_pull_${collection.name}');
    final remoteRecords = await _backend.listChangedSince(
      collection.name,
      cursor,
    );
    if (remoteRecords.isEmpty) return;

    DateTime? maxSeen;
    for (final remote in remoteRecords) {
      final entityId = remote['entity_id']! as String;
      // Cursor advancement uses PocketBase's own server-assigned
      // `server_updated` (monotonic, immune to client clock skew), not
      // the client-set `updated_at` used below for LWW.
      final serverUpdated = DateTime.parse(remote['server_updated']! as String);
      if (maxSeen == null || serverUpdated.isAfter(maxSeen)) {
        maxSeen = serverUpdated;
      }

      // LWW comparison uses the client-set `updated_at` — when each
      // device's user actually made the edit, not when it happened to
      // reach the server.
      final remoteUpdatedAt = DateTime.parse(remote['updated_at']! as String);
      final localRecord = await collection.store.record(entityId).get(_db);
      final localUpdatedAt = localRecord == null
          ? _epoch
          : DateTime.parse(localRecord['updatedAt']! as String);
      if (!remoteUpdatedAt.isAfter(localUpdatedAt)) continue;

      final data = Map<String, Object?>.from(
        remote['data']! as Map<Object?, Object?>,
      );
      await collection.store.record(entityId).put(_db, data, merge: true);
    }
    if (maxSeen != null) {
      await _settings.setValue(
        'sync_pull_${collection.name}',
        maxSeen.toIso8601String(),
      );
    }
  }

  Future<DateTime> _cursor(String key) async {
    final stored = await _settings.getValue(key);
    return stored == null ? _epoch : DateTime.parse(stored);
  }
}
