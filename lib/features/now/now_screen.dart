import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/widgets/colored_list_card.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/day/date_format.dart';
import 'package:taskframe/features/day/day_blocks_provider.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/now/now_selection.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/task_card.dart';

/// How many of the current frame's oldest open, active tasks to show.
const _maxFrameTasks = 3;

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// The "Now" view: today's previous/current/next-two blocks at a glance,
/// plus — when the current block is a [BlockKind.frame] — the category's
/// oldest open, active tasks below it.
class NowScreen extends ConsumerWidget {
  /// Creates a [NowScreen].
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocksAsync = ref.watch(dayBlocksProvider(_today()));

    return Scaffold(
      appBar: AppBar(leading: const SizedBox(), title: const Text('Now')),
      body: blocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load: $error')),
        data: (blocks) => _NowBody(blocks: blocks),
      ),
    );
  }
}

class _NowBody extends ConsumerWidget {
  const new({required this.blocks});

  final List<TimeObject> blocks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = selectNowEvents(blocks, DateTime.now());
    final categories = ref.watch(categoryListProvider).value ?? const [];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _EventSlot(
          label: 'Previous',
          block: selection.previous,
          categories: categories,
        ),
        _EventSlot(
          label: 'Current',
          block: selection.current,
          categories: categories,
          emphasize: true,
        ),
        _EventSlot(
          label: 'Next',
          block: selection.next1,
          extraBlock: selection.next2,
          categories: categories,
        ),
        if (selection.current?.kind == BlockKind.frame)
          _FrameTasks(categoryId: selection.current!.categoryId),
      ],
    );
  }
}

/// One row of the "Now" view: a labeled slot showing [block] (or a muted
/// placeholder when there's nothing there), plus an optional second card
/// for [extraBlock] — shown only when it exists, with no label or
/// placeholder of its own, so an empty second slot is simply omitted
/// rather than announced.
class _EventSlot extends StatelessWidget {
  const new({
    required this.label,
    required this.block,
    required this.categories,
    this.extraBlock,
    this.emphasize = false,
  });

  final String label;
  final TimeObject? block;
  final TimeObject? extraBlock;
  final List<Category> categories;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (block == null)
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                title: Text(
                  'Nothing scheduled',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            _BlockCard(
              block: block!,
              categories: categories,
              emphasize: emphasize,
            ),
          if (extraBlock != null) ...[
            const SizedBox(height: 8),
            _BlockCard(
              block: extraBlock!,
              categories: categories,
              emphasize: false,
            ),
          ],
        ],
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const new({
    required this.block,
    required this.categories,
    required this.emphasize,
  });

  final TimeObject block;
  final List<Category> categories;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final category = categories.isEmpty
        ? null
        : categoryById(categories, block.categoryId);
    final color = category == null
        ? Theme.of(context).colorScheme.primaryContainer
        : Color(category.colorValue);
    final title = category?.formatTitle(block.title) ?? block.title;

    return ColoredListCard(
      color: color,
      title: Text(
        title,
        style: TextStyle(fontWeight: emphasize ? FontWeight.bold : null),
      ),
      trailing: Text('${formatHm(block.start)}–${formatHm(block.end)}'),
    );
  }
}

/// The current frame's oldest [_maxFrameTasks] open, active tasks in
/// [categoryId], each tappable to close directly (via [TaskCard]).
class _FrameTasks extends ConsumerWidget {
  const new({required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(taskListProvider);
    final tasks = tasksAsync.value ?? const <Task>[];
    final relevant = [
      for (final t in tasks)
        if (t.categoryId == categoryId && !t.closed && !t.isNotYetActive) t,
    ]..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final shown = relevant.take(_maxFrameTasks).toList();

    if (shown.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Frame tasks',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final task in shown) TaskCard(task: task, onTap: () {}),
        ],
      ),
    );
  }
}
