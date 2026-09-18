import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/models/task.dart';

/// Loads and stores the flat list of tasks.
///
/// Implementations back this with whatever storage is appropriate (in
/// memory today, sembast for real persistence); callers depend only on
/// this interface.
abstract class TaskRepository {
  /// Returns every task, in creation order.
  Future<List<Task>> load();

  /// Creates a new, open task and returns it. [categoryId] defaults to
  /// [Category.defaultId] when omitted.
  Future<Task> add({
    required String title,
    String? categoryId,
    DateTime? activeFrom,
  });

  /// Updates [task] in place, replacing any of [title]/[closed]/
  /// [categoryId]/[tags]/[activeFrom]/[repeat] that are given and leaving
  /// the rest unchanged. [activeFrom]/[repeat] are left unchanged when
  /// omitted; pass [clearActiveFrom]/[clearRepeat] to remove them
  /// instead. Returns the updated task.
  Future<Task> update(
    Task task, {
    String? title,
    bool? closed,
    String? categoryId,
    List<String>? tags,
    DateTime? activeFrom,
    bool clearActiveFrom = false,
    String? repeat,
    bool clearRepeat = false,
  });

  /// Removes [task].
  Future<void> delete(Task task);
}

/// A [TaskRepository] that keeps tasks in memory for the life of the app,
/// starting empty.
class InMemoryTaskRepository implements TaskRepository {
  final List<Task> _tasks = [];
  int _nextId = 0;

  @override
  Future<List<Task>> load() async => List.unmodifiable(_tasks);

  @override
  Future<Task> add({
    required String title,
    String? categoryId,
    DateTime? activeFrom,
  }) async {
    final task = Task(
      id: 'task-${_nextId++}',
      title: title,
      categoryId: categoryId ?? Category.defaultId,
      activeFrom: activeFrom,
    );
    _tasks.add(task);
    return task;
  }

  @override
  Future<Task> update(
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
    final updated = task.copyWith(
      title: title,
      closed: closed,
      categoryId: categoryId,
      tags: tags,
      activeFrom: activeFrom,
      clearActiveFrom: clearActiveFrom,
      repeat: repeat,
      clearRepeat: clearRepeat,
    );
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index == -1) {
      throw StateError('Task ${task.id} not found');
    }
    _tasks[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(Task task) async {
    _tasks.removeWhere((t) => t.id == task.id);
  }
}
