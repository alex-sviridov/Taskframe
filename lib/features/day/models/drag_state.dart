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

  /// The date the landzone shadow is currently shown on.
  final DateTime targetDate;

  /// The 15-minute-grid-aligned time the landzone shadow currently starts
  /// at.
  final DateTime targetStart;

  /// The dragging pointer's last known position in global (screen)
  /// coordinates, used for edge-triggered day/week paging.
  final Offset pointerGlobalPosition;

  /// Returns a copy of this state with the given fields replaced.
  DragState copyWith({
    DateTime? targetDate,
    DateTime? targetStart,
    Offset? pointerGlobalPosition,
  }) {
    return DragState(
      block: block,
      originalDate: originalDate,
      targetDate: targetDate ?? this.targetDate,
      targetStart: targetStart ?? this.targetStart,
      pointerGlobalPosition:
          pointerGlobalPosition ?? this.pointerGlobalPosition,
    );
  }
}
