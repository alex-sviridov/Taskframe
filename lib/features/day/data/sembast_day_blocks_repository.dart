import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/date_key.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A [DayBlocksRepository] backed by a sembast [Database], persisting
/// blocks across restarts. Each record's key is the block's own `id`;
/// `load` filters records by a stored `dateKey` field (see [dateKeyFor]).
class SembastDayBlocksRepository implements DayBlocksRepository {
  /// Creates a [SembastDayBlocksRepository] reading/writing [_db].
  new(this._db);

  final Database _db;

  @override
  Future<List<TimeObject>> load(DateTime date) async {
    final finder = Finder(
      filter: Filter.equals('dateKey', dateKeyFor(date)),
      sortOrders: [SortOrder('start')],
    );
    final records = await dayBlocksStore.find(_db, finder: finder);
    return [for (final record in records) TimeObject.fromMap(record.value)];
  }

  @override
  Future<TimeObject> add(
    DateTime date, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  }) async {
    final block = TimeObject(
      id: _uuid.v4(),
      title: title ?? 'title',
      start: start,
      end: end,
      kind: kind,
      locked: false,
      categoryId: categoryId ?? Category.defaultId,
    );
    await dayBlocksStore.record(block.id).put(_db, {
      ...block.toMap(),
      'dateKey': dateKeyFor(date),
    });
    return block;
  }

  @override
  Future<TimeObject> move(
    TimeObject block, {
    required DateTime fromDate,
    required DateTime toDate,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final moved = TimeObject(
      id: block.id,
      title: block.title,
      start: newStart,
      end: newEnd,
      kind: block.kind,
      locked: block.locked,
      categoryId: block.categoryId,
    );
    await dayBlocksStore.record(block.id).put(_db, {
      ...moved.toMap(),
      'dateKey': dateKeyFor(toDate),
    });
    return moved;
  }

  @override
  Future<TimeObject> update(
    TimeObject block, {
    required DateTime date,
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  }) async {
    final updated = TimeObject(
      id: block.id,
      title: title ?? block.title,
      start: start ?? block.start,
      end: end ?? block.end,
      kind: kind ?? block.kind,
      locked: block.locked,
      categoryId: categoryId ?? block.categoryId,
    );
    await dayBlocksStore.record(block.id).put(_db, {
      ...updated.toMap(),
      'dateKey': dateKeyFor(date),
    });
    return updated;
  }

  @override
  Future<void> delete(TimeObject block, {required DateTime date}) async {
    await dayBlocksStore.record(block.id).delete(_db);
  }
}
