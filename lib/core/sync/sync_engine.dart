import 'dart:async';

import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/sync_collection.dart';

/// The result of one [SyncEngine.syncAll] call.
class SyncOutcome {
  /// Creates a [SyncOutcome].
  const new({required this.changed, required this.hadError});

  /// The names of the collections that actually had at least one remote
  /// record applied to local storage this call (i.e. a pull that won
  /// LWW) — a pushed-only or no-op collection is never included.
  final Set<String> changed;

  /// Whether any collection's push or pull failed this call (e.g. a
  /// network error, or no/dead session) — always best-effort and
  /// retried on the next trigger, never thrown. A caller (e.g. a sync
  /// status indicator) uses this to tell "sync is working" from "sync
  /// is currently failing", which [changed] alone can't: an empty
  /// [changed] set is also the normal, healthy outcome of "nothing new
  /// to pull".
  final bool hadError;
}

/// What [SyncEngine] needs from a remote backend. `PocketBaseSyncClient`
/// (see `pocketbase_sync_client.dart`) is the real implementation; tests
/// use an in-memory fake.
abstract class SyncBackend {
  /// Creates or updates the remote record for `record['entity_id']`, in
  /// PocketBase collection [collection]. [record] is the full local
  /// sembast map for that entity (it must contain `id`, `updatedAt`,
  /// `deleted`).
  ///
  /// [remoteId] is this entity's PocketBase record id if already known
  /// (from an earlier push or pull of the same entity — see
  /// `sync_collection.dart`'s `remoteIdStore`), letting the
  /// implementation go straight to a single `update` call instead of
  /// first querying PocketBase to check whether the record exists.
  /// `null` means this entity has never been seen remotely before — the
  /// implementation must `create` it. Returns the entity's PocketBase
  /// record id either way, for the caller to remember for next time.
  Future<String> upsert(
    String collection,
    Map<String, Object?> record, {
    String? remoteId,
  });

  /// Returns every remote record in [collection] whose PocketBase-managed
  /// `server_updated` timestamp is strictly after [cursor]. Each returned
  /// map has `entity_id`, `remote_id` (this record's PocketBase id, for
  /// `remoteIdStore`), `updated_at` (the client-set last-write-wins
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
  /// Creates a [SyncEngine].
  new({
    required Database db,
    required AppSettingsRepository settings,
    required SyncBackend backend,
    // The public parameter names (db/settings/backend) are kept distinct
    // from the private field names (_db/_settings/_backend) on purpose —
    // an initializing formal would force the param name to match the
    // field name exactly, making every call site pass `_db:`/`_settings:`
    // /`_backend:`, which reads worse than the current, deliberate names.
    // ignore: prefer_initializing_formals
  }) : _db = db,
       // Same reasoning as above: keep the public param name `settings`.
       // ignore: prefer_initializing_formals
       _settings = settings,
       // Same reasoning as above: keep the public param name `backend`.
       // ignore: prefer_initializing_formals
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
  ///
  /// See [SyncOutcome] for what's returned — a caller (see
  /// `sync_trigger.dart`) uses it both to refresh only the UI state that
  /// actually changed and to report sync health (e.g. a status
  /// indicator) without this method needing to throw for a failure it
  /// already intends to retry on its own.
  Future<SyncOutcome> syncAll(List<SyncCollection> collections) {
    return runExclusive(() async {
      final changed = <String>{};
      var hadError = false;
      for (final collection in collections) {
        try {
          if (await _pull(collection)) changed.add(collection.name);
        } on Object {
          // Best-effort; retried on the next trigger.
          hadError = true;
        }
        try {
          if (!await _push(collection)) hadError = true;
        } on Object {
          // Best-effort; retried on the next trigger.
          hadError = true;
        }
      }
      return SyncOutcome(changed: changed, hadError: hadError);
    });
  }

  /// Returns whether every locally-changed record was pushed
  /// successfully — `false` means at least one failed (see the
  /// per-record `break` below) and will be retried on the next trigger.
  Future<bool> _push(SyncCollection collection) async {
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
    if (records.isEmpty) return true;

    var succeeded = true;
    DateTime? maxSeen;
    for (final record in records) {
      final entityId = record.key;
      final updatedAt = DateTime.parse(record.value['updatedAt']! as String);
      final idKey = remoteIdKey(collection.name, entityId);
      final knownIdRecord = await remoteIdStore.record(idKey).get(_db);
      final knownRemoteId = knownIdRecord?['id'] as String?;
      try {
        final remoteId = await _backend.upsert(collection.name, {
          ...record.value,
          'entity_id': entityId,
        }, remoteId: knownRemoteId);
        await remoteIdStore.record(idKey).put(_db, {'id': remoteId});
      } on Object {
        // Stop here rather than propagating: everything up to this point
        // already succeeded and its cursor progress below must not be
        // lost. This record (and anything after it) is retried on the
        // next trigger.
        succeeded = false;
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
    return succeeded;
  }

  /// Returns whether any remote record was actually applied to local
  /// storage (i.e. won LWW) — see [syncAll]'s returned set.
  Future<bool> _pull(SyncCollection collection) async {
    final cursor = await _cursor('sync_pull_${collection.name}');
    final remoteRecords = await _backend.listChangedSince(
      collection.name,
      cursor,
    );
    if (remoteRecords.isEmpty) return false;

    var applied = false;
    DateTime? maxSeen;
    for (final remote in remoteRecords) {
      final entityId = remote['entity_id']! as String;
      // Learned regardless of who wins LWW below: even when the local
      // copy stays newer (remote discarded), this device now knows the
      // entity's remote id — without this, its next push of that
      // not-yet-pushed local edit would `create` a duplicate remote
      // record instead of updating the one that already exists.
      final remoteId = remote['remote_id'] as String?;
      if (remoteId != null) {
        await remoteIdStore.record(remoteIdKey(collection.name, entityId)).put(
          _db,
          {'id': remoteId},
        );
      }
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
      applied = true;
    }
    if (maxSeen != null) {
      await _settings.setValue(
        'sync_pull_${collection.name}',
        maxSeen.toIso8601String(),
      );
    }
    return applied;
  }

  Future<DateTime> _cursor(String key) async {
    final stored = await _settings.getValue(key);
    return stored == null ? _epoch : DateTime.parse(stored);
  }
}
