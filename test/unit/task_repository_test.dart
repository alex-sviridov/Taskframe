// test/unit/task_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/data/task_repository.dart';

void main() {
  group('InMemoryTaskRepository', () {
    late InMemoryTaskRepository repository;

    setUp(() => repository = InMemoryTaskRepository());

    test('load starts empty', () async {
      expect(await repository.load(), isEmpty);
    });

    test('add appends a new open task with the default category', () async {
      final added = await repository.add(title: 'Buy milk');

      expect(added.title, 'Buy milk');
      expect(added.closed, isFalse);
      expect(added.categoryId, Category.defaultId);
    });

    test('add accepts an explicit categoryId', () async {
      final added = await repository.add(
        title: 'Buy milk',
        categoryId: 'category-1',
      );

      expect(added.categoryId, 'category-1');
    });

    test('two added tasks get distinct ids', () async {
      final first = await repository.add(title: 'First');
      final second = await repository.add(title: 'Second');

      expect(first.id, isNot(equals(second.id)));
    });

    test('added tasks show up in a later load, in creation order', () async {
      await repository.add(title: 'First');
      await repository.add(title: 'Second');

      final tasks = await repository.load();

      expect(tasks.map((t) => t.title), ['First', 'Second']);
    });

    test('update changes title/closed/categoryId/tags', () async {
      final added = await repository.add(title: 'Buy milk');

      final updated = await repository.update(
        added,
        title: 'Buy oat milk',
        closed: true,
        categoryId: 'category-1',
        tags: ['errands'],
      );

      expect(updated.id, added.id);
      expect(updated.title, 'Buy oat milk');
      expect(updated.closed, isTrue);
      expect(updated.categoryId, 'category-1');
      expect(updated.tags, ['errands']);
    });

    test('update leaves fields unspecified as null unchanged', () async {
      final added = await repository.add(
        title: 'Buy milk',
        categoryId: 'category-1',
      );

      final updated = await repository.update(added, closed: true);

      expect(updated.title, 'Buy milk');
      expect(updated.categoryId, 'category-1');
    });

    test('update replaces the task in a later load', () async {
      final added = await repository.add(title: 'Buy milk');

      await repository.update(added, title: 'Buy oat milk');

      final tasks = await repository.load();
      expect(tasks.singleWhere((t) => t.id == added.id).title, 'Buy oat milk');
    });

    test('delete removes a task from a later load', () async {
      final added = await repository.add(title: 'Buy milk');

      await repository.delete(added);

      final tasks = await repository.load();
      expect(tasks.where((t) => t.id == added.id), isEmpty);
    });
  });
}
