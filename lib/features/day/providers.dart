import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
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

/// Tracks the block currently being dragged to a new time/date, if any.
///
/// `null` when no drag is in progress. Read by any visible `DayGrid`
/// column to render the landzone shadow, and by `DayScreen` to drive
/// edge-triggered day/week paging.
class DragNotifier extends Notifier<DragState?> {
  @override
  DragState? build() => null;

  /// Begins dragging [block], which belonged to [originalDate]. The
  /// landzone starts at the block's own current date/time.
  void start({
    required TimeObject block,
    required DateTime originalDate,
    required Offset pointerGlobalPosition,
  }) {
    state = DragState(
      block: block,
      originalDate: originalDate,
      targetDate: originalDate,
      targetStart: block.start,
      pointerGlobalPosition: pointerGlobalPosition,
    );
  }

  /// Updates the dragging pointer's position. If [targetDate]/
  /// [targetStart] are given (the pointer is over a valid day column),
  /// the landzone moves there; otherwise only the pointer position
  /// updates, leaving the last valid landzone showing. Does nothing if no
  /// drag is in progress.
  void updatePointer(
    Offset globalPosition, {
    DateTime? targetDate,
    DateTime? targetStart,
  }) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      targetDate: targetDate,
      targetStart: targetStart,
      pointerGlobalPosition: globalPosition,
    );
  }

  /// Commits the current drag: moves the block to its current landzone
  /// date/time via the repository, refreshes both the origin and target
  /// day's blocks, then clears the drag. Does nothing if no drag is in
  /// progress.
  Future<void> drop() async {
    final current = state;
    if (current == null) return;
    state = null;

    final duration = current.block.end.difference(current.block.start);
    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.move(
      current.block,
      fromDate: current.originalDate,
      toDate: current.targetDate,
      newStart: current.targetStart,
      newEnd: current.targetStart.add(duration),
    );

    ref.invalidate(dayBlocksProvider(current.originalDate));
    ref.invalidate(dayBlocksProvider(current.targetDate));
    await ref.read(dayBlocksProvider(current.originalDate).future);
    await ref.read(dayBlocksProvider(current.targetDate).future);
  }

  /// Abandons the current drag without moving the block.
  void cancel() {
    state = null;
  }
}

/// The block currently being dragged to a new time/date, if any.
final dragStateProvider = NotifierProvider<DragNotifier, DragState?>(
  DragNotifier.new,
);
