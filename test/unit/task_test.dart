import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/models/task.dart';

void main() {
  group('Task', () {
    test('closed defaults to false', () {
      const task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.closed, isFalse);
    });

    test('categoryId defaults to Category.defaultId', () {
      const task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.categoryId, Category.defaultId);
    });

    test('tags defaults to empty', () {
      const task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.tags, isEmpty);
    });

    test('copyWith replaces only the given fields', () {
      const task = Task(
        id: 'task-1',
        title: 'Buy milk',
        categoryId: 'category-1',
      );

      final updated = task.copyWith(title: 'Buy oat milk', closed: true);

      expect(updated.id, 'task-1');
      expect(updated.title, 'Buy oat milk');
      expect(updated.closed, isTrue);
      expect(updated.categoryId, 'category-1');
    });

    test('copyWith replaces tags', () {
      const task = Task(id: 'task-1', title: 'Buy milk', tags: ['home']);

      final updated = task.copyWith(tags: ['home', 'errands']);

      expect(updated.tags, ['home', 'errands']);
    });

    test('copyWith with no arguments returns equivalent fields', () {
      const task = Task(
        id: 'task-1',
        title: 'Buy milk',
        closed: true,
        categoryId: 'category-1',
        tags: ['home'],
      );

      final copy = task.copyWith();

      expect(copy.id, task.id);
      expect(copy.title, task.title);
      expect(copy.closed, task.closed);
      expect(copy.categoryId, task.categoryId);
      expect(copy.tags, task.tags);
    });
  });

  group('toMap/fromMap', () {
    test('fromMap(toMap()) round-trips every field', () {
      const task = Task(
        id: 'task-1',
        title: 'Buy milk',
        closed: true,
        categoryId: 'category-1',
        tags: ['home', 'errands'],
      );

      final restored = Task.fromMap(task.toMap());

      expect(restored.id, task.id);
      expect(restored.title, task.title);
      expect(restored.closed, task.closed);
      expect(restored.categoryId, task.categoryId);
      expect(restored.tags, task.tags);
    });

    test('fromMap defaults tags to empty when the map has no tags key '
        '(a task persisted before tags existed)', () {
      final restored = Task.fromMap({
        'id': 'task-1',
        'title': 'Buy milk',
        'closed': false,
        'categoryId': 'category-1',
      });

      expect(restored.tags, isEmpty);
    });
  });
}
