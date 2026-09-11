import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/widgets/schedule_block_actions.dart';

DateTime _dateOf(ScheduleColumn column) => (column as DayColumn).date;

List<TimeObject>? _watchDayBlocks(WidgetRef ref, ScheduleColumn column) =>
    ref.watch(dayBlocksProvider(_dateOf(column))).value;

Future<void> _updateDayBlock(
  WidgetRef ref,
  ScheduleColumn column,
  TimeObject block, {
  String? title,
  DateTime? start,
  DateTime? end,
  BlockKind? kind,
  String? categoryId,
}) => ref
    .read(dayBlocksProvider(_dateOf(column)).notifier)
    .updateBlock(
      block,
      title: title,
      start: start,
      end: end,
      kind: kind,
      categoryId: categoryId,
    );

Future<void> _deleteDayBlock(
  WidgetRef ref,
  ScheduleColumn column,
  TimeObject block,
) => ref.read(dayBlocksProvider(_dateOf(column)).notifier).deleteBlock(block);

/// The [ScheduleBlockActions] `BlockEditModal` uses when editing a day
/// block. Every [ScheduleColumn] passed to it must be a [DayColumn].
const dayScheduleBlockActions = ScheduleBlockActions(
  watchBlocks: _watchDayBlocks,
  updateBlock: _updateDayBlock,
  deleteBlock: _deleteDayBlock,
);
