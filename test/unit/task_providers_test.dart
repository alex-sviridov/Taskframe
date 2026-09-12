// test/unit/task_providers_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/task/data/task_repository.dart';
import 'package:taskframe/features/task/providers.dart';

void main() {
  group('taskListProvider', () {
    test('loads the repository tasks (empty to start)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final tasks = await container.read(taskListProvider.future);
      final expected = await InMemoryTaskRepository().load();

      expect(tasks.map((t) => t.id), expected.map((t) => t.id));
    });

    test('addTask appends the new task returned by the repository', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(taskListProvider.future);

      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.where((t) => t.title == 'Buy milk'), hasLength(1));
    });

    test('addTask returns the created task', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(taskListProvider.future);

      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk', categoryId: 'category-1');

      expect(created.title, 'Buy milk');
      expect(created.categoryId, 'category-1');
    });

    test('updateTask persists a title/closed/category change', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(taskListProvider.future);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');

      await container
          .read(taskListProvider.notifier)
          .updateTask(created, title: 'Buy oat milk', closed: true);

      final tasks = container.read(taskListProvider).value!;
      final updated = tasks.singleWhere((t) => t.id == created.id);
      expect(updated.title, 'Buy oat milk');
      expect(updated.closed, isTrue);
    });

    test('deleteTask removes the task from state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(taskListProvider.future);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');

      await container.read(taskListProvider.notifier).deleteTask(created);

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.where((t) => t.id == created.id), isEmpty);
    });
  });
}
