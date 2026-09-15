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

  /// Returns every remote record in [collection] whose `updated_at` is
  /// strictly after [cursor]. Each returned map has `entity_id`,
  /// `updated_at`, `deleted`, and `data` (the original local sembast map
  /// as pushed by [upsert]).
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

  /// Runs pull then push for every collection in [collections], so a
  /// concurrently-newer remote change is absorbed locally before this
  /// device publishes its own changes (avoiding a stale local push
  /// clobbering a fresher remote record). A failure syncing one
  /// collection (e.g. a network error) is swallowed so the others still
  /// get a chance — matches the spec's "push/pull fail silently,
  /// retried on the next trigger".
  Future<void> syncAll(List<SyncCollection> collections) async {
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
  }

  Future<void> _push(SyncCollection collection) async {
    final cursor = await _cursor('sync_push_${collection.name}');
    final finder = Finder(
      filter: Filter.greaterThan('updatedAt', cursor.toIso8601String()),
    );
    final records = await collection.store.find(_db, finder: finder);
    if (records.isEmpty) return;

    DateTime? maxSeen;
    for (final record in records) {
      await _backend.upsert(collection.name, {
        ...record.value,
        'entity_id': record.key,
      });
      final updatedAt = DateTime.parse(record.value['updatedAt']! as String);
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
      final remoteUpdatedAt = DateTime.parse(remote['updated_at']! as String);
      if (maxSeen == null || remoteUpdatedAt.isAfter(maxSeen)) {
        maxSeen = remoteUpdatedAt;
      }

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
