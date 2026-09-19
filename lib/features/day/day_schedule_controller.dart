import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/day_blocks_provider.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/schedule_controller.dart';

/// A [ScheduleController] backed by [dayBlocksProvider]/
/// [dayBlocksRepositoryProvider]. Every [ScheduleColumn] it's given must
/// be a [DayColumn].
class DayScheduleController extends ScheduleController {
  /// Creates a [DayScheduleController].
  const new();

  DateTime _dateOf(ScheduleColumn column) => (column as DayColumn).date;

  @override
  List<TimeObject>? blocksOf(Ref ref, ScheduleColumn column) =>
      ref.read(dayBlocksProvider(_dateOf(column))).value;

  @override
  Future<void> moveBlock(
    Ref ref, {
    required TimeObject block,
    required ScheduleColumn fromColumn,
    required ScheduleColumn toColumn,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final fromDate = _dateOf(fromColumn);
    final toDate = _dateOf(toColumn);
    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.move(
      block,
      fromDate: fromDate,
      toDate: toDate,
      newStart: newStart,
      newEnd: newEnd,
    );
    ref
      ..invalidate(dayBlocksProvider(fromDate))
      ..invalidate(dayBlocksProvider(toDate));
    await ref.read(dayBlocksProvider(fromDate).future);
    await ref.read(dayBlocksProvider(toDate).future);
  }
}
