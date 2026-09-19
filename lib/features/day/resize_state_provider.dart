import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/schedule_controller.dart';

/// The shortest duration a block can be resized down to.
const _minBlockDuration = Duration(minutes: 15);

/// Tracks the block currently being resized by dragging one of its edges,
/// if any.
///
/// `null` when no resize is in progress. A resize never changes a block's
/// date, so unlike [DragNotifier] this needs no pointer-ownership dance —
/// the widget driving the drag stays mounted for its whole lifetime.
class ResizeNotifier extends Notifier<ResizeState?> {
  ScheduleController? _controller;

  @override
  ResizeState? build() => null;

  /// Begins resizing [block] on [column] from [edge]. The draft starts out
  /// equal to the block's own current start/end. [controller] is used for
  /// every subsequent read/commit this resize makes.
  void start({
    required TimeObject block,
    required ScheduleColumn column,
    required ScheduleController controller,
    required ResizeEdge edge,
  }) {
    _controller = controller;
    state = ResizeState(
      block: block,
      column: column,
      edge: edge,
      draftStart: block.start,
      draftEnd: block.end,
    );
  }

  /// Updates the dragged edge's draft time to [candidate] (already
  /// snapped to the 15-minute grid), clamped so the block never shrinks
  /// below [_minBlockDuration] and never overlaps another block on
  /// [ResizeState.column].
  void update(DateTime candidate) {
    final current = state;
    if (current == null) return;
    final others = (_controller?.blocksOf(ref, current.column) ?? []).where(
      (block) => block.id != current.block.id,
    );

    if (current.edge == ResizeEdge.end) {
      var newEnd = candidate;
      final minEnd = current.draftStart.add(_minBlockDuration);
      if (newEnd.isBefore(minEnd)) newEnd = minEnd;
      for (final block in others) {
        if (block.start.isAfter(current.draftStart) &&
            block.start.isBefore(newEnd)) {
          newEnd = block.start;
        }
      }
      state = current.copyWith(draftEnd: newEnd);
    } else {
      var newStart = candidate;
      final maxStart = current.draftEnd.subtract(_minBlockDuration);
      if (newStart.isAfter(maxStart)) newStart = maxStart;
      for (final block in others) {
        if (block.end.isBefore(current.draftEnd) &&
            block.end.isAfter(newStart)) {
          newStart = block.end;
        }
      }
      state = current.copyWith(draftStart: newStart);
    }
  }

  /// Commits the current resize: persists the draft start/end via
  /// [_controller], then clears the resize. Does nothing if no resize is
  /// in progress.
  Future<void> commit() async {
    final current = state;
    if (current == null) return;
    final controller = _controller!;
    state = null;

    await controller.moveBlock(
      ref,
      block: current.block,
      fromColumn: current.column,
      toColumn: current.column,
      newStart: current.draftStart,
      newEnd: current.draftEnd,
    );
  }

  /// Abandons the current resize without changing the block.
  void cancel() {
    state = null;
  }
}

/// The block currently being resized, if any.
final resizeStateProvider = NotifierProvider<ResizeNotifier, ResizeState?>(
  ResizeNotifier.new,
);

/// Projects [resizeState] to the value a `DayGrid` for [column] actually
/// cares about, collapsing to `null` whenever the resize belongs to some
/// other column. See [dragStateForColumn], its drag equivalent.
ResizeState? resizeStateForColumn(
  ResizeState? resizeState,
  ScheduleColumn column,
) {
  if (resizeState == null) return null;
  return resizeState.column == column ? resizeState : null;
}
