import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// Reads and moves the blocks belonging to a [ScheduleColumn], hiding
/// whether they're backed by the day feature's providers (a [DayColumn])
/// or a template's own providers (a [TemplateColumn]) from the shared
/// drag/resize code in `providers.dart` — `DragNotifier`/`ResizeNotifier`
/// never need to know which.
abstract class ScheduleController {
  /// Const constructor for subclasses.
  const new();

  /// The currently loaded blocks for [column], or `null` while still
  /// loading.
  List<TimeObject>? blocksOf(Ref ref, ScheduleColumn column);

  /// Moves [block] from [fromColumn] to [toColumn] (the same column for a
  /// resize, which never changes column), updating its start/end to
  /// [newStart]/[newEnd], then refreshes both columns' providers.
  Future<void> moveBlock(
    Ref ref, {
    required TimeObject block,
    required ScheduleColumn fromColumn,
    required ScheduleColumn toColumn,
    required DateTime newStart,
    required DateTime newEnd,
  });
}
