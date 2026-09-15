import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/data/task_repository.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A [TaskRepository] backed by a sembast [Database], persisting tasks
/// across restarts. Records are keyed by [Task.id]; an `order` field (set
/// once at creation) keeps [load] in creation order.
class SembastTaskRepository implements TaskRepository {
  /// Creates a [SembastTaskRepository] reading/writing [_db].
  new(this._db);

  final Database _db;

  @override
  Future<List<Task>> load() async {
    final finder = Finder(
      filter: Filter.notEquals('deleted', true),
      sortOrders: [SortOrder('order')],
    );
    final records = await tasksStore.find(_db, finder: finder);
    return [for (final record in records) Task.fromMap(record.value)];
  }

  @override
  Future<Task> add({required String title, String? categoryId}) async {
    final task = Task(
      id: _uuid.v4(),
      title: title,
      categoryId: categoryId ?? Category.defaultId,
      updatedAt: DateTime.now().toUtc(),
    );
    await tasksStore.record(task.id).put(_db, {
      ...task.toMap(),
      'order': DateTime.now().microsecondsSinceEpoch,
    });
    return task;
  }

  @override
  Future<Task> update(
    Task task, {
    String? title,
    bool? closed,
    String? categoryId,
    List<String>? tags,
  }) async {
    final existingRecord = await tasksStore.record(task.id).get(_db);
    final current = existingRecord == null
        ? task
        : Task.fromMap(existingRecord);
    final updated = current.copyWith(
      title: title,
      closed: closed,
      categoryId: categoryId,
      tags: tags,
      updatedAt: DateTime.now().toUtc(),
    );
    final order =
        existingRecord?['order'] ?? DateTime.now().microsecondsSinceEpoch;
    await tasksStore.record(updated.id).put(_db, {
      ...updated.toMap(),
      'order': order,
    });
    return updated;
  }

  @override
  Future<void> delete(Task task) async {
    final existingRecord = await tasksStore.record(task.id).get(_db);
    final current = existingRecord == null
        ? task
        : Task.fromMap(existingRecord);
    final tombstone = current.copyWith(
      deleted: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await tasksStore.record(task.id).put(_db, {
      ...tombstone.toMap(),
      'order': existingRecord?['order'] ?? 0,
    });
  }
}
