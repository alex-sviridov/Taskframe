import 'package:taskframe/features/day/models/time_object.dart';

/// Loads and stores the timeline blocks for a given date.
///
/// Implementations back this with whatever storage is appropriate (in
/// memory today, an API later); callers depend only on this interface.
abstract class DayBlocksRepository {
  /// Returns the blocks for [date].
  Future<List<TimeObject>> load(DateTime date);

  /// Creates a new block on [date] and returns it.
  Future<TimeObject> add(
    DateTime date, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
  });
}

/// A [DayBlocksRepository] that keeps added blocks in memory for the life
/// of the app, seeded with a hardcoded set of blocks for today.
class InMemoryDayBlocksRepository implements DayBlocksRepository {
  final Map<DateTime, List<TimeObject>> _added = {};
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
  }) async {
    final block = TimeObject(
      id: 'block-${_nextId++}',
      title: 'title',
      start: start,
      end: end,
      kind: kind,
      locked: false,
    );

    final key = _dateKey(date);
    _added[key] = [...?_added[key], block];
    return block;
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
    ];
  }
}
