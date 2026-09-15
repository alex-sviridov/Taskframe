import 'package:taskframe/features/day/models/schedule_column.dart';

/// The in-flight state of a new block's draft, placed but not yet created.
///
/// `null` (held by `draftStateProvider`, not this class) means no draft is
/// currently open. There is only ever one draft across every column at
/// once — opening a new one (on this or another column) replaces whatever
/// was open before.
class DraftState {
  /// Creates a [DraftState].
  const new({required this.column, required this.start, required this.end});

  /// The column this draft belongs to.
  final ScheduleColumn column;

  /// The draft's current (15-minute-grid-aligned) start time.
  final DateTime start;

  /// The draft's current (15-minute-grid-aligned) end time.
  final DateTime end;

  /// Returns a copy of this state with the given fields replaced.
  DraftState copyWith({DateTime? start, DateTime? end}) {
    return DraftState(
      column: column,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}
