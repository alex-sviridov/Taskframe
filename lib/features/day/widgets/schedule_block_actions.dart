import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// The read/write operations [BlockEditModal] needs on the blocks
/// belonging to whichever [ScheduleColumn] it's editing, supplied by the
/// caller (`DayScreen` for a [DayColumn], `TemplatesScreen` for a
/// [TemplateColumn]) so this shared widget never imports either feature's
/// own providers directly.
class ScheduleBlockActions {
  const ScheduleBlockActions({
    required this.watchBlocks,
    required this.updateBlock,
    required this.deleteBlock,
  });

  /// Watches (reactively) the current blocks for [column], or `null`
  /// while still loading. Must be called from a widget's `build`, so
  /// implementations should `ref.watch`, not `ref.read`.
  final List<TimeObject>? Function(WidgetRef ref, ScheduleColumn column)
  watchBlocks;

  /// Updates [block] (which belongs to [column]), replacing any of
  /// [title]/[start]/[end]/[kind]/[categoryId] that are given.
  final Future<void> Function(
    WidgetRef ref,
    ScheduleColumn column,
    TimeObject block, {
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  })
  updateBlock;

  /// Removes [block] (which belongs to [column]).
  final Future<void> Function(
    WidgetRef ref,
    ScheduleColumn column,
    TimeObject block,
  )
  deleteBlock;
}
