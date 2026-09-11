import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// Which edge of a block a resize drag is moving.
enum ResizeEdge {
  /// The drag is moving the block's start time.
  start,

  /// The drag is moving the block's end time.
  end,
}

/// The in-flight state of a block being resized by dragging one of its
/// edges.
///
/// `null` (held by `resizeStateProvider`, not this class) means no resize
/// is in progress.
class ResizeState {
  /// Creates a [ResizeState].
  const ResizeState({
    required this.block,
    required this.column,
    required this.edge,
    required this.draftStart,
    required this.draftEnd,
  });

  /// The block being resized, as it was before the resize started.
  final TimeObject block;

  /// The column [block] belongs to. Resizing never changes it.
  final ScheduleColumn column;

  /// Which edge of the block is being dragged.
  final ResizeEdge edge;

  /// The 15-minute-grid-aligned, clamped start time the draft shadow
  /// currently shows.
  final DateTime draftStart;

  /// The 15-minute-grid-aligned, clamped end time the draft shadow
  /// currently shows.
  final DateTime draftEnd;

  /// Returns a copy of this state with the given fields replaced.
  ResizeState copyWith({DateTime? draftStart, DateTime? draftEnd}) {
    return ResizeState(
      block: block,
      column: column,
      edge: edge,
      draftStart: draftStart ?? this.draftStart,
      draftEnd: draftEnd ?? this.draftEnd,
    );
  }
}
