import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/draft_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';

/// Tracks the single new-block draft open across every column, if any.
///
/// There is only ever one draft at a time regardless of how many columns
/// are on screen (e.g. week view): [openAt] always replaces whatever draft
/// was open before, on this or any other column, so placing a new draft
/// implicitly destroys the previous one.
class DraftNotifier extends Notifier<DraftState?> {
  @override
  DraftState? build() => null;

  /// Opens (or replaces) the draft on [column], spanning `[start, end)`.
  void openAt({
    required ScheduleColumn column,
    required DateTime start,
    required DateTime end,
  }) {
    state = DraftState(column: column, start: start, end: end);
  }

  /// Updates the open draft's range. Does nothing if no draft is open.
  void updateRange({required DateTime start, required DateTime end}) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(start: start, end: end);
  }

  /// Closes the open draft, if any, without creating a block.
  void dismiss() {
    state = null;
  }
}

/// The single new-block draft open across every column, if any.
final draftStateProvider = NotifierProvider<DraftNotifier, DraftState?>(
  DraftNotifier.new,
);

/// Projects [draftState] to the value a `DayGrid` for [column] actually
/// cares about, collapsing to `null` whenever the draft belongs to some
/// other column. See dragStateForColumn (in drag_state_provider.dart) for
/// the drag equivalent.
DraftState? draftStateForColumn(DraftState? draftState, ScheduleColumn column) {
  if (draftState == null) return null;
  return draftState.column == column ? draftState : null;
}
