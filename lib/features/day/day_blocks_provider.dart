import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/template_apply.dart';
import 'package:taskframe/features/template/providers.dart';

/// The backing store for day blocks.
///
/// Overriding this single provider (e.g. with an API-backed
/// [DayBlocksRepository]) is enough to change where blocks are loaded from
/// and saved to; nothing downstream needs to change.
final dayBlocksRepositoryProvider = Provider<DayBlocksRepository>(
  (ref) => InMemoryDayBlocksRepository(),
);

/// Holds the timeline blocks for one date, loaded from
/// [dayBlocksRepositoryProvider], and lets the day screen add new ones.
class DayBlocksNotifier extends AsyncNotifier<List<TimeObject>> {
  /// Creates a [DayBlocksNotifier] for [date].
  new(this.date);

  /// The date this notifier's blocks belong to.
  final DateTime date;

  @override
  Future<List<TimeObject>> build() =>
      ref.watch(dayBlocksRepositoryProvider).load(date);

  /// Creates a new block on [date], adds it to the current state, and
  /// returns it.
  Future<TimeObject> addBlock({
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  }) async {
    final repository = ref.read(dayBlocksRepositoryProvider);
    final added = await repository.add(
      date,
      start: start,
      end: end,
      kind: kind,
      title: title,
      categoryId: categoryId,
    );
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Updates [block]'s title/start/end/kind, persisting via the repository
  /// and refreshing state. Silently does nothing if the resulting start/end
  /// would be invalid (see [isValidBlockEdit]) — title/kind-only edits are
  /// always valid since they don't touch start/end.
  Future<void> updateBlock(
    TimeObject block, {
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  }) async {
    final newStart = start ?? block.start;
    final newEnd = end ?? block.end;
    final others = (state.value ?? []).where((b) => b.id != block.id).toList();
    final settings = ref.read(daySettingsProvider);
    if (!isValidBlockEdit(
      start: newStart,
      end: newEnd,
      settings: settings,
      day: date,
      others: others,
    )) {
      return;
    }

    final repository = ref.read(dayBlocksRepositoryProvider);
    final updated = await repository.update(
      block,
      date: date,
      title: title,
      start: start,
      end: end,
      kind: kind,
      categoryId: categoryId,
    );
    state = AsyncData([
      for (final b in state.value ?? <TimeObject>[])
        if (b.id == block.id) updated else b,
    ]);
  }

  /// Removes [block], persisting via the repository and refreshing state.
  Future<void> deleteBlock(TimeObject block) async {
    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.delete(block, date: date);
    state = AsyncData([
      for (final b in state.value ?? <TimeObject>[])
        if (b.id != block.id) b,
    ]);
  }

  /// Adds a copy of [block] (same title/kind/duration, same time of day) to
  /// the following date's blocks.
  Future<void> copyToNextDay(TimeObject block) async {
    final nextDate = DateTime(date.year, date.month, date.day + 1);
    final duration = block.end.difference(block.start);
    final nextStart = DateTime(
      nextDate.year,
      nextDate.month,
      nextDate.day,
      block.start.hour,
      block.start.minute,
    );
    await ref
        .read(dayBlocksProvider(nextDate).notifier)
        .addBlock(
          start: nextStart,
          end: nextStart.add(duration),
          kind: block.kind,
          title: block.title,
          categoryId: block.categoryId,
        );
  }

  /// Applies [templateId]'s blocks to [date]: each is rebased onto this
  /// day's time-of-day and added unless it overlaps an existing block (or
  /// another template block already accepted in this same apply), per
  /// [resolveTemplateApply]. Partial — a conflicting block is skipped
  /// rather than aborting the whole apply.
  Future<TemplateApplyResult> applyTemplate(String templateId) async {
    final templateBlocks = await ref.read(
      templateBlocksProvider(templateId).future,
    );
    final resolved = resolveTemplateApply(
      templateBlocks: templateBlocks,
      dayBlocks: state.value ?? [],
      date: date,
    );

    final addedIds = <String>[];
    for (final block in resolved.toAdd) {
      final created = await addBlock(
        start: block.start,
        end: block.end,
        kind: block.kind,
        title: block.title,
        categoryId: block.categoryId,
      );
      addedIds.add(created.id);
    }

    return (addedIds: addedIds, skipped: resolved.skipped);
  }
}

/// The timeline blocks for a given date.
// ignore: specify_nonobvious_property_types
final dayBlocksProvider =
    AsyncNotifierProvider.family<DayBlocksNotifier, List<TimeObject>, DateTime>(
      DayBlocksNotifier.new,
    );
