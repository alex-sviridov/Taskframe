import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/task_card.dart';
import 'package:taskframe/features/task/widgets/task_edit_modal.dart';

/// Lists every task as a [TaskCard], in creation order, and lets the user
/// add or edit one via [showTaskEditModal]. Closing a task is a checkbox
/// on its own card — see [TaskCard] — so this screen only wires up
/// add/open-for-edit.
class TasksScreen extends ConsumerWidget {
  /// Creates a [TasksScreen].
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(taskListProvider);

    return Scaffold(
      appBar: AppBar(
        // Reserves the leading slot so AppShell's floating hamburger button
        // (narrow widths only) has room without covering the title.
        leading: const SizedBox(),
        title: const Text('Tasks'),
        actions: [
          IconButton(
            tooltip: 'Add task',
            icon: const Icon(Icons.add),
            onPressed: () => showTaskEditModal(context: context),
          ),
        ],
      ),
      body: switch (tasksAsync) {
        AsyncData(:final value) => LayoutBuilder(
          builder: (context, constraints) {
            final isNarrowWidth = constraints.maxWidth < narrowBreakpoint;
            final list = ListView(
              padding: isNarrowWidth
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final task in value)
                  TaskCard(
                    task: task,
                    onTap: () =>
                        showTaskEditModal(context: context, task: task),
                  ),
              ],
            );
            if (isNarrowWidth) return list;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: list,
              ),
            );
          },
        ),
        AsyncError() => const Center(child: Text('Failed to load tasks')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
