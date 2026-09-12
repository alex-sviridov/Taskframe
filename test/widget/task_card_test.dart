// test/widget/task_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/task_card.dart';

Future<ProviderContainer> _seededContainer() async {
  final container = ProviderContainer();
  await container.read(categoryListProvider.future);
  await container.read(taskListProvider.future);
  return container;
}

Future<void> _pumpCard(
  WidgetTester tester,
  ProviderContainer container,
  Task task, {
  VoidCallback? onTap,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: TaskCard(task: task, onTap: onTap ?? () {}),
      ),
    ),
  ),
);

void main() {
  group('TaskCard', () {
    testWidgets('shows the task title', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');

      await _pumpCard(tester, container, task);

      expect(find.text('Buy milk'), findsOneWidget);
    });

    testWidgets('prefixes the title with the category emoji when it has one', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final category = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Ship it', categoryId: category.id);

      await _pumpCard(tester, container, task);

      expect(find.text('💼 Ship it'), findsOneWidget);
    });

    testWidgets('uses the category color as its background', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final category = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3);
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Ship it', categoryId: category.id);

      await _pumpCard(tester, container, task);

      final container2 = tester.widget<Container>(
        find.ancestor(
          of: find.text('Ship it'),
          matching: find.byType(Container),
        ),
      );
      final decoration = container2.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF2196F3));
    });

    testWidgets('shows a checked checkbox for a closed task', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      final closed = await container
          .read(taskListProvider.notifier)
          .updateTask(task, closed: true)
          .then((_) => task.copyWith(closed: true));

      await _pumpCard(tester, container, closed);

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isTrue);
    });

    testWidgets('tapping the checkbox toggles closed via the provider', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');

      await _pumpCard(tester, container, task);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.single.closed, isTrue);
    });

    testWidgets('tapping the card body (not the checkbox) calls onTap', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      var tapped = false;

      await _pumpCard(tester, container, task, onTap: () => tapped = true);
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });
}
