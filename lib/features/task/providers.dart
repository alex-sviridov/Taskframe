import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/task/data/task_repository.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/repeat_parsing.dart';

/// The backing store for tasks.
///
/// Overriding this single provider (e.g. with the sembast-backed
/// implementation) is enough to change where tasks are loaded from and
/// saved to; nothing downstream needs to change.
final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => InMemoryTaskRepository(),
);

/// Holds the list of tasks, loaded from [taskRepositoryProvider], and
/// lets consumers add/update/delete them.
class TaskListNotifier extends AsyncNotifier<List<Task>> {
  @override
  Future<List<Task>> build() => ref.watch(taskRepositoryProvider).load();

  /// Creates a new task, adds it to the current state, and returns it.
  Future<Task> addTask({
    required String title,
    String? categoryId,
    DateTime? activeFrom,
  }) async {
    final repository = ref.read(taskRepositoryProvider);
    final added = await repository.add(
      title: title,
      categoryId: categoryId,
      activeFrom: activeFrom,
    );
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Updates [task]'s title/closed/category/tags/activeFrom/repeat,
  /// persisting via the repository and refreshing state. [activeFrom]/
  /// [repeat] are left unchanged when omitted; pass [clearActiveFrom]/
  /// [clearRepeat] to remove them instead.
  ///
  /// Closing a task (`closed: true`, transitioning from an open task)
  /// that has a [Task.repeat] set spawns its successor: a fresh task
  /// with the same title/category/tags/repeat, open, and active from
  /// [nextOccurrence] of now. Reopening a task, or closing one that's
  /// already closed, never spawns.
  Future<void> updateTask(
    Task task, {
    String? title,
    bool? closed,
    String? categoryId,
    List<String>? tags,
    DateTime? activeFrom,
    bool clearActiveFrom = false,
    String? repeat,
    bool clearRepeat = false,
  }) async {
    final repository = ref.read(taskRepositoryProvider);
    final updated = await repository.update(
      task,
      title: title,
      closed: closed,
      categoryId: categoryId,
      tags: tags,
      activeFrom: activeFrom,
      clearActiveFrom: clearActiveFrom,
      repeat: repeat,
      clearRepeat: clearRepeat,
    );
    state = AsyncData([
      for (final t in state.value ?? <Task>[])
        if (t.id == task.id) updated else t,
    ]);

    if (closed == true && !task.closed && updated.repeat != null) {
      final successor = await repository.add(
        title: updated.title,
        categoryId: updated.categoryId,
        activeFrom: nextOccurrence(DateTime.now(), updated.repeat!),
      );
      final withTagsAndRepeat = await repository.update(
        successor,
        tags: updated.tags,
        repeat: updated.repeat,
      );
      state = AsyncData([...?state.value, withTagsAndRepeat]);
    }
  }

  /// Removes [task], persisting via the repository and refreshing state.
  Future<void> deleteTask(Task task) async {
    final repository = ref.read(taskRepositoryProvider);
    await repository.delete(task);
    state = AsyncData([
      for (final t in state.value ?? <Task>[])
        if (t.id != task.id) t,
    ]);
  }
}

/// The list of tasks.
final taskListProvider = AsyncNotifierProvider<TaskListNotifier, List<Task>>(
  TaskListNotifier.new,
);
