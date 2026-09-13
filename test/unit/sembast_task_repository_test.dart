import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/data/sembast_task_repository.dart';

void main() {
  group('SembastTaskRepository', () {
    late Database db;
    late SembastTaskRepository repository;

    setUp(() async {
      db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastTaskRepository(db);
    });

    test(
      'loads a task record stored before tags existed (no tags field)',
      () async {
        await tasksStore.record('legacy-task').put(db, {
          'id': 'legacy-task',
          'title': 'Buy milk',
          'closed': false,
          'categoryId': Category.defaultId,
          'order': 0,
        });

        final tasks = await repository.load();

        expect(tasks.single.title, 'Buy milk');
        expect(tasks.single.tags, isEmpty);
      },
    );

    test('load starts empty', () async {
      expect(await repository.load(), isEmpty);
    });

    test('add appends a new open task with the default category', () async {
      final added = await repository.add(title: 'Buy milk');

      expect(added.closed, isFalse);
      expect(added.categoryId, Category.defaultId);
      final tasks = await repository.load();
      expect(tasks, hasLength(1));
    });

    test('two added tasks get distinct ids', () async {
      final first = await repository.add(title: 'First');
      final second = await repository.add(title: 'Second');

      expect(first.id, isNot(second.id));
    });

    test('added tasks load back in creation order', () async {
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

      expect(updated.title, 'Buy oat milk');
      expect(updated.closed, isTrue);
      expect(updated.categoryId, 'category-1');
      expect(updated.tags, ['errands']);
    });

    test('tags persist through a later load', () async {
      final added = await repository.add(title: 'Buy milk');
      await repository.update(added, tags: ['errands']);

      final tasks = await repository.load();

      expect(tasks.singleWhere((t) => t.id == added.id).tags, ['errands']);
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
