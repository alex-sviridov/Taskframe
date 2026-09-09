import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/models/time_object.dart';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Holds the date currently shown on the day screen, normalized to
/// midnight.
class SelectedDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => _today();

  /// The selected date. Settable directly so the day view can follow its
  /// own swipe/page navigation.
  DateTime get date => state;
  set date(DateTime value) => state = value;
}

/// The date currently shown on the day screen.
final selectedDateProvider = NotifierProvider<SelectedDateNotifier, DateTime>(
  SelectedDateNotifier.new,
);

/// The backing store for day blocks.
///
/// Overriding this single provider (e.g. with an API-backed
/// [DayBlocksRepository]) is enough to change where blocks are loaded from
/// and saved to; nothing downstream needs to change.
final dayBlocksRepositoryProvider = Provider<DayBlocksRepository>(
  (ref) => InMemoryDayBlocksRepository(),
);

/// Holds the timeline blocks for one date, loaded from
/// [dayBlocksRepositoryProvider], and lets the day screen add new ones.
class DayBlocksNotifier extends AsyncNotifier<List<TimeObject>> {
  /// Creates a [DayBlocksNotifier] for [date].
  new(this.date);

  /// The date this notifier's blocks belong to.
  final DateTime date;

  @override
  Future<List<TimeObject>> build() =>
      ref.watch(dayBlocksRepositoryProvider).load(date);

  /// Creates a new block on [date] and adds it to the current state.
  Future<void> addBlock({
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
  }) async {
    final repository = ref.read(dayBlocksRepositoryProvider);
    final added = await repository.add(
      date,
      start: start,
      end: end,
      kind: kind,
    );
    state = AsyncData([...?state.value, added]);
  }
}

/// The timeline blocks for a given date.
// ignore: specify_nonobvious_property_types
final dayBlocksProvider =
    AsyncNotifierProvider.family<DayBlocksNotifier, List<TimeObject>, DateTime>(
      DayBlocksNotifier.new,
    );
