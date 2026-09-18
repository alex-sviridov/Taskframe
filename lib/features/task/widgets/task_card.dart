import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/widgets/colored_list_card.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/task/active_from_parsing.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/tag_pills.dart';

/// Renders a single [Task] in the tasks list: a filled card using its
/// category's color (falling back to the theme's own color while
/// categories are still loading, matching `BlockView`'s fallback) and the
/// category's emoji prefixed onto the title, with a leading checkbox that
/// toggles [Task.closed] directly — no need to open the edit modal just
/// to close a task. Closed tasks show their title struck through and
/// dimmed. Tapping the rest of the card calls [onTap]. Built on
/// [ColoredListCard], shared with the categories list, so its background
/// is the category color itself, matching `BlockView`'s own approach.
class TaskCard extends ConsumerWidget {
  /// Creates a [TaskCard] for [task].
  const new({required this.task, required this.onTap, super.key});

  /// The task to render.
  final Task task;

  /// Called when the card body (outside the checkbox) is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final categories = ref.watch(categoryListProvider).value ?? const [];
    final category = categories.isEmpty
        ? null
        : categoryById(categories, task.categoryId);
    final categoryColor = category == null ? null : Color(category.colorValue);
    final title = category?.formatTitle(task.title) ?? task.title;
    final notYetActive = task.isNotYetActive;

    return ColoredListCard(
      color: categoryColor ?? scheme.primaryContainer,
      leading: Checkbox(
        shape: const CircleBorder(),
        value: task.closed,
        onChanged: (value) => ref
            .read(taskListProvider.notifier)
            .updateTask(task, closed: value ?? !task.closed),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              decoration: task.closed ? TextDecoration.lineThrough : null,
              color: task.closed || notYetActive
                  ? Theme.of(context).disabledColor
                  : null,
              fontStyle: notYetActive ? FontStyle.italic : null,
            ),
          ),
          if (task.tags.isNotEmpty || notYetActive) const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (notYetActive)
                Chip(
                  label: Text('from ${formatActiveFrom(task.activeFrom!)}'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              TagPills(tags: task.tags),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
