import 'package:flutter/material.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// The in-flight state of a block being dragged to a new time/column.
///
/// `null` (held by `dragStateProvider`, not this class) means no drag is
/// in progress.
class DragState {
  /// Creates a [DragState].
  const DragState({
    required this.block,
    required this.originalColumn,
    required this.targetColumn,
    required this.targetStart,
    required this.pointerGlobalPosition,
  });

  /// The block being dragged, as it was before the drag started.
  final TimeObject block;

  /// The column [block] belonged to when the drag started.
  final ScheduleColumn originalColumn;

  /// The column the landzone shadow is currently shown on, or `null` when
  /// the pointer is over no column at all — in which case releasing here
  /// would cancel the move, and no landzone is drawn anywhere.
  final ScheduleColumn? targetColumn;

  /// The 15-minute-grid-aligned time the landzone shadow currently starts
  /// at, or `null` alongside a `null` [targetColumn].
  final DateTime? targetStart;

  /// The dragging pointer's last known position in global (screen)
  /// coordinates, used for edge-triggered day/week paging.
  final Offset pointerGlobalPosition;

  /// Whether the drag currently has a valid landzone to drop onto.
  bool get hasTarget => targetColumn != null && targetStart != null;

  /// Returns a copy of this state with the given fields replaced.
  ///
  /// Pass [clearTarget] to drop the landzone entirely (the pointer is over
  /// no column); it wins over [targetColumn]/[targetStart], which
  /// otherwise keep their current values when omitted.
  DragState copyWith({
    ScheduleColumn? targetColumn,
    DateTime? targetStart,
    Offset? pointerGlobalPosition,
    bool clearTarget = false,
  }) {
    return DragState(
      block: block,
      originalColumn: originalColumn,
      targetColumn: clearTarget ? null : (targetColumn ?? this.targetColumn),
      targetStart: clearTarget ? null : (targetStart ?? this.targetStart),
      pointerGlobalPosition:
          pointerGlobalPosition ?? this.pointerGlobalPosition,
    );
  }
}
