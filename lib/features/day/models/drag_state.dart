import 'package:flutter/material.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// The in-flight state of a block being dragged to a new time/date.
///
/// `null` (held by `dragStateProvider`, not this class) means no drag is
/// in progress.
class DragState {
  /// Creates a [DragState].
  const DragState({
    required this.block,
    required this.originalDate,
    required this.targetDate,
    required this.targetStart,
    required this.pointerGlobalPosition,
  });

  /// The block being dragged, as it was before the drag started.
  final TimeObject block;

  /// The date [block] belonged to when the drag started.
  final DateTime originalDate;

  /// The date the landzone shadow is currently shown on, or `null` when the
  /// pointer is over no day column at all — in which case releasing here
  /// would cancel the move, and no landzone is drawn anywhere.
  final DateTime? targetDate;

  /// The 15-minute-grid-aligned time the landzone shadow currently starts
  /// at, or `null` alongside a `null` [targetDate].
  final DateTime? targetStart;

  /// The dragging pointer's last known position in global (screen)
  /// coordinates, used for edge-triggered day/week paging.
  final Offset pointerGlobalPosition;

  /// Whether the drag currently has a valid landzone to drop onto.
  bool get hasTarget => targetDate != null && targetStart != null;

  /// Returns a copy of this state with the given fields replaced.
  ///
  /// Pass [clearTarget] to drop the landzone entirely (the pointer is over
  /// no column); it wins over [targetDate]/[targetStart], which otherwise
  /// keep their current values when omitted.
  DragState copyWith({
    DateTime? targetDate,
    DateTime? targetStart,
    Offset? pointerGlobalPosition,
    bool clearTarget = false,
  }) {
    return DragState(
      block: block,
      originalDate: originalDate,
      targetDate: clearTarget ? null : (targetDate ?? this.targetDate),
      targetStart: clearTarget ? null : (targetStart ?? this.targetStart),
      pointerGlobalPosition:
          pointerGlobalPosition ?? this.pointerGlobalPosition,
    );
  }
}
