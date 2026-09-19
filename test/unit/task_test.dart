import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/models/task.dart';

void main() {
  group('Task', () {
    test('closed defaults to false', () {
      final task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.closed, isFalse);
    });

    test('categoryId defaults to Category.defaultId', () {
      final task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.categoryId, Category.defaultId);
    });

    test('tags defaults to empty', () {
      final task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.tags, isEmpty);
    });

    test('activeFrom defaults to null', () {
      final task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.activeFrom, isNull);
    });

    test('copyWith sets activeFrom', () {
      final task = Task(id: 'task-1', title: 'Buy milk');
      final activeFrom = DateTime.utc(2026, 3, 5);

      final updated = task.copyWith(activeFrom: activeFrom);

      expect(updated.activeFrom, activeFrom);
    });

    test('copyWith with no arguments leaves an existing activeFrom '
        'unchanged', () {
      final activeFrom = DateTime.utc(2026, 3, 5);
      final task = Task(
        id: 'task-1',
        title: 'Buy milk',
        activeFrom: activeFrom,
      );

      final copy = task.copyWith();

      expect(copy.activeFrom, activeFrom);
    });

    test('copyWith(clearActiveFrom: true) removes an existing activeFrom', () {
      final task = Task(
        id: 'task-1',
        title: 'Buy milk',
        activeFrom: DateTime.utc(2026, 3, 5),
      );

      final updated = task.copyWith(clearActiveFrom: true);

      expect(updated.activeFrom, isNull);
    });

    test('repeat defaults to null', () {
      final task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.repeat, isNull);
    });

    test('copyWith sets repeat', () {
      final task = Task(id: 'task-1', title: 'Buy milk');

      final updated = task.copyWith(repeat: '1w');

      expect(updated.repeat, '1w');
    });

    test('copyWith with no arguments leaves an existing repeat unchanged', () {
      final task = Task(id: 'task-1', title: 'Buy milk', repeat: '1w');

      final copy = task.copyWith();

      expect(copy.repeat, '1w');
    });

    test('copyWith(clearRepeat: true) removes an existing repeat', () {
      final task = Task(id: 'task-1', title: 'Buy milk', repeat: '1w');

      final updated = task.copyWith(clearRepeat: true);

      expect(updated.repeat, isNull);
    });

    test('copyWith replaces only the given fields', () {
      final task = Task(
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
      final task = Task(id: 'task-1', title: 'Buy milk', tags: ['home']);

      final updated = task.copyWith(tags: ['home', 'errands']);

      expect(updated.tags, ['home', 'errands']);
    });

    test('copyWith with no arguments returns equivalent fields', () {
      final task = Task(
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

  group('isNotYetActive', () {
    test('is false when activeFrom is null', () {
      final task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.isNotYetActive, isFalse);
    });

    test('is false when activeFrom is in the past', () {
      final task = Task(
        id: 'task-1',
        title: 'Buy milk',
        activeFrom: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(task.isNotYetActive, isFalse);
    });

    test('is true when activeFrom is in the future', () {
      final task = Task(
        id: 'task-1',
        title: 'Buy milk',
        activeFrom: DateTime.now().add(const Duration(days: 1)),
      );

      expect(task.isNotYetActive, isTrue);
    });
  });

  group('toMap/fromMap', () {
    test('fromMap(toMap()) round-trips every field', () {
      final task = Task(
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

    test('fromMap(toMap()) round-trips a set activeFrom', () {
      final task = Task(
        id: 'task-1',
        title: 'Buy milk',
        activeFrom: DateTime.utc(2026, 3, 5),
      );

      final restored = Task.fromMap(task.toMap());

      expect(restored.activeFrom, task.activeFrom);
    });

    test('fromMap defaults activeFrom to null when the map has no '
        'activeFrom key', () {
      final restored = Task.fromMap({
        'id': 'task-1',
        'title': 'Buy milk',
        'closed': false,
        'categoryId': 'category-1',
      });

      expect(restored.activeFrom, isNull);
    });

    test('fromMap(toMap()) round-trips a set repeat', () {
      final task = Task(id: 'task-1', title: 'Buy milk', repeat: '1w');

      final restored = Task.fromMap(task.toMap());

      expect(restored.repeat, '1w');
    });

    test('fromMap defaults repeat to null when the map has no repeat key', () {
      final restored = Task.fromMap({
        'id': 'task-1',
        'title': 'Buy milk',
        'closed': false,
        'categoryId': 'category-1',
      });

      expect(restored.repeat, isNull);
    });

    test('toMap/fromMap round-trip updatedAt and deleted', () {
      final updatedAt = DateTime.utc(2026, 9, 15, 12);
      final task = Task(
        id: 't1',
        title: 'Buy milk',
        updatedAt: updatedAt,
        deleted: true,
      );
      final restored = Task.fromMap(task.toMap());
      expect(restored.updatedAt, updatedAt);
      expect(restored.deleted, isTrue);
    });

    test(
      'fromMap defaults deleted to false and updatedAt to epoch when absent',
      () {
        final restored = Task.fromMap({
          'id': 't1',
          'title': 'Buy milk',
          'closed': false,
          'categoryId': Category.defaultId,
        });
        expect(restored.deleted, isFalse);
        expect(restored.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
      },
    );
  });
}
