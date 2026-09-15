import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// Loads and stores the timeline blocks for a given date.
///
/// Implementations back this with whatever storage is appropriate (in
/// memory today, an API later); callers depend only on this interface.
abstract class DayBlocksRepository {
  /// Returns the blocks for [date].
  Future<List<TimeObject>> load(DateTime date);

  /// Creates a new block on [date] and returns it. [title] defaults to an
  /// empty string when omitted.
  Future<TimeObject> add(
    DateTime date, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  });

  /// Moves [block] from [fromDate] to [toDate], updating its start/end to
  /// [newStart]/[newEnd], and returns the updated block. [fromDate] and
  /// [toDate] may be the same date.
  Future<TimeObject> move(
    TimeObject block, {
    required DateTime fromDate,
    required DateTime toDate,
    required DateTime newStart,
    required DateTime newEnd,
  });

  /// Updates [block] (which belongs to [date]) in place, replacing any of
  /// [title]/[start]/[end]/[kind]/[categoryId] that are given and leaving
  /// the rest unchanged. Returns the updated block.
  Future<TimeObject> update(
    TimeObject block, {
    required DateTime date,
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  });

  /// Removes [block] (which belongs to [date]).
  Future<void> delete(TimeObject block, {required DateTime date});
}

/// A [DayBlocksRepository] that keeps added blocks in memory for the life
/// of the app, seeded with a hardcoded set of blocks for today.
class InMemoryDayBlocksRepository implements DayBlocksRepository {
  final Map<DateTime, List<TimeObject>> _added = {};
  final Set<String> _movedSeedIds = {};
  int _nextId = 0;

  @override
  Future<List<TimeObject>> load(DateTime date) async {
    return [..._seedFor(date), ...?_added[_dateKey(date)]];
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
      id: 'block-${_nextId++}',
      title: title ?? '',
      start: start,
      end: end,
      kind: kind,
      locked: false,
      categoryId: categoryId ?? Category.defaultId,
    );

    final key = _dateKey(date);
    _added[key] = [...?_added[key], block];
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
    final fromKey = _dateKey(fromDate);
    final toKey = _dateKey(toDate);

    final fromList = _added[fromKey];
    if (fromList != null && fromList.any((b) => b.id == block.id)) {
      _added[fromKey] = fromList.where((b) => b.id != block.id).toList();
    } else {
      _movedSeedIds.add(block.id);
    }

    final moved = TimeObject(
      id: block.id,
      title: block.title,
      start: newStart,
      end: newEnd,
      kind: block.kind,
      locked: block.locked,
      categoryId: block.categoryId,
    );

    _added[toKey] = [...?_added[toKey], moved];
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
    final key = _dateKey(date);
    final updated = TimeObject(
      id: block.id,
      title: title ?? block.title,
      start: start ?? block.start,
      end: end ?? block.end,
      kind: kind ?? block.kind,
      locked: block.locked,
      categoryId: categoryId ?? block.categoryId,
    );

    final list = _added[key];
    if (list != null && list.any((b) => b.id == block.id)) {
      _added[key] = [
        for (final b in list)
          if (b.id == block.id) updated else b,
      ];
    } else {
      // A seeded block being edited for the first time: promote it into
      // `_added` and suppress the stale seed, the same way `move` does.
      _movedSeedIds.add(block.id);
      _added[key] = [...?_added[key], updated];
    }
    return updated;
  }

  @override
  Future<void> delete(TimeObject block, {required DateTime date}) async {
    final key = _dateKey(date);
    final list = _added[key];
    if (list != null && list.any((b) => b.id == block.id)) {
      _added[key] = list.where((b) => b.id != block.id).toList();
    } else {
      _movedSeedIds.add(block.id);
    }
  }

  static DateTime _dateKey(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  List<TimeObject> _seedFor(DateTime date) {
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    if (!isToday) {
      return [];
    }

    DateTime at(int hour, [int minute = 0]) =>
        DateTime(today.year, today.month, today.day, hour, minute);

    return [
      TimeObject(
        id: 'breakfast',
        title: 'Breakfast',
        start: at(7),
        end: at(7, 30),
        kind: BlockKind.anchor,
        locked: false,
      ),
      TimeObject(
        id: 'commute',
        title: 'Commute',
        start: at(8),
        end: at(8, 30),
        kind: BlockKind.anchor,
        locked: false,
      ),
      TimeObject(
        id: 'work',
        title: 'Work',
        start: at(9),
        end: at(13),
        kind: BlockKind.frame,
        locked: false,
      ),
      TimeObject(
        id: 'lunch',
        title: 'Lunch',
        start: at(13),
        end: at(13, 30),
        kind: BlockKind.anchor,
        locked: false,
      ),
      TimeObject(
        id: 'cleaning',
        title: 'Cleaning',
        start: at(19),
        end: at(20),
        kind: BlockKind.frame,
        locked: false,
      ),
    ].where((block) => !_movedSeedIds.contains(block.id)).toList();
  }
}
