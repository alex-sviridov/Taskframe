// test/widget/task_edit_modal_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/task_edit_modal.dart';

Future<ProviderContainer> _seededContainer() async {
  final container = ProviderContainer();
  await container.read(categoryListProvider.future);
  await container.read(taskListProvider.future);
  return container;
}

Future<void> _pumpOpenButton(
  WidgetTester tester,
  ProviderContainer container, {
  Task? task,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showTaskEditModal(context: context, task: task),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('TaskEditModal', () {
    testWidgets('create mode: entering a title and saving adds a task', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.where((t) => t.title == 'Buy milk'), hasLength(1));
    });

    testWidgets('create mode: Save is disabled while the title is empty', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('create mode: shows no Delete action', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('edit mode: pre-fills the title field', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pumpOpenButton(tester, container, task: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Buy milk'), findsOneWidget);
    });

    testWidgets('edit mode: changing the title and saving persists it', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pumpOpenButton(tester, container, task: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Buy oat milk');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      final updatedTask = tasks.singleWhere((t) => t.id == created.id);
      expect(updatedTask.title, 'Buy oat milk');
    });

    testWidgets(
      'edit mode: toggling the Closed switch and saving persists it',
      (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pumpOpenButton(tester, container, task: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.singleWhere((t) => t.id == created.id).closed, isTrue);
    });

    testWidgets('edit mode: Delete asks for confirmation, then removes the '
        'task', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pumpOpenButton(tester, container, task: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.where((t) => t.id == created.id), isEmpty);
    });

    testWidgets('Cancel dismisses the modal without saving changes', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.where((t) => t.title == 'Buy milk'), isEmpty);
    });
  });
}
