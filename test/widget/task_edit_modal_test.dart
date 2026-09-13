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
    testWidgets('the title field is autofocused when the modal opens', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final titleField = tester.widget<TextField>(find.byType(TextField));
      expect(titleField.autofocus, isTrue);
    });

    testWidgets('shows no Save/Cancel buttons', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    group('create mode', () {
      testWidgets('shows no Delete action before anything is typed', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Delete'), findsNothing);
      });

      testWidgets('typing a title creates the task live, no Save needed', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Buy milk');
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks.where((t) => t.title == 'Buy milk'), hasLength(1));
      });

      testWidgets('the Delete action appears once the task is created', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Buy milk');
        await tester.pump();

        expect(find.text('Delete'), findsOneWidget);
      });

      testWidgets(
        'toggling Closed before typing applies once the task is created',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          await _pumpOpenButton(tester, container);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(Checkbox));
          await tester.pump();
          await tester.enterText(find.byType(TextField), 'Buy milk');
          await tester.pump();

          final tasks = container.read(taskListProvider).value!;
          expect(
            tasks.singleWhere((t) => t.title == 'Buy milk').closed,
            isTrue,
          );
        },
      );

      testWidgets(
        'picking a category before typing applies once the task is created',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          final work = await container
              .read(categoryListProvider.notifier)
              .addCategory(name: 'Work', colorValue: 0xFF2196F3);
          await _pumpOpenButton(tester, container);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DropdownButtonFormField<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Work').last);
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'Buy milk');
          await tester.pump();

          final tasks = container.read(taskListProvider).value!;
          expect(
            tasks.singleWhere((t) => t.title == 'Buy milk').categoryId,
            work.id,
          );
        },
      );

      testWidgets('typing further keystrokes updates the same task, not a '
          'new one', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Buy');
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Buy milk');
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks, hasLength(1));
        expect(tasks.single.title, 'Buy milk');
      });

      testWidgets('typing "#tag " strips it from the title and adds a tag', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Buy #groceries ');
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks, hasLength(1));
        expect(tasks.single.title, 'Buy ');
        expect(tasks.single.tags, ['groceries']);
      });

      testWidgets('the tag pill shows after typing "#tag "', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Buy #groceries ');
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('groceries'), findsOneWidget);
      });

      testWidgets(
        'rapid same-tick keystrokes (real typing, faster than one addTask '
        'round-trip) still create only one task',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          await _pumpOpenButton(tester, container);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          // enterText/pump always lets the prior onChanged's Future resolve
          // first, so it can't reproduce the race a fast typist causes:
          // several onChanged calls fired before the first addTask
          // round-trip completes. Call the field's own onChanged directly,
          // back-to-back with no await between calls, to reproduce that.
          final onChanged = tester
              .widget<TextField>(find.byType(TextField))
              .onChanged!;
          onChanged('B');
          onChanged('Bu');
          onChanged('Buy');
          await tester.pumpAndSettle();

          final tasks = container.read(taskListProvider).value!;
          expect(tasks, hasLength(1));
          expect(tasks.single.title, 'Buy');
        },
      );
    });

    group('edit mode', () {
      testWidgets('pre-fills the title field', (tester) async {
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

      testWidgets('typing a new title updates it live, no Save needed', (
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

        final tasks = container.read(taskListProvider).value!;
        final updatedTask = tasks.singleWhere((t) => t.id == created.id);
        expect(updatedTask.title, 'Buy oat milk');
      });

      testWidgets('toggling Closed updates it live and strikes the title', (
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
        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks.singleWhere((t) => t.id == created.id).closed, isTrue);
        final titleField = tester.widget<TextField>(find.byType(TextField));
        expect(titleField.style?.decoration, TextDecoration.lineThrough);
      });

      testWidgets('picking a category updates it live', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final work = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        final created = await container
            .read(taskListProvider.notifier)
            .addTask(title: 'Buy milk');
        await _pumpOpenButton(tester, container, task: created);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Work').last);
        await tester.pumpAndSettle();

        final tasks = container.read(taskListProvider).value!;
        expect(
          tasks.singleWhere((t) => t.id == created.id).categoryId,
          work.id,
        );
      });

      testWidgets('shows an existing tag as a pill', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(taskListProvider.notifier)
            .addTask(title: 'Buy milk');
        await container
            .read(taskListProvider.notifier)
            .updateTask(created, tags: ['groceries']);
        final tagged = container
            .read(taskListProvider)
            .value!
            .singleWhere((t) => t.id == created.id);
        await _pumpOpenButton(tester, container, task: tagged);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('groceries'), findsOneWidget);
      });

      testWidgets('typing "#tag " in edit mode adds a tag pill', (
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
        await tester.enterText(find.byType(TextField), 'Buy milk #errands ');
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        final updated = tasks.singleWhere((t) => t.id == created.id);
        expect(updated.title, 'Buy milk ');
        expect(updated.tags, ['errands']);
      });

      testWidgets('tapping a pill delete icon removes that tag', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(taskListProvider.notifier)
            .addTask(title: 'Buy milk');
        await container
            .read(taskListProvider.notifier)
            .updateTask(created, tags: ['groceries', 'errands']);
        final tagged = container
            .read(taskListProvider)
            .value!
            .singleWhere((t) => t.id == created.id);
        await _pumpOpenButton(tester, container, task: tagged);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.widgetWithText(InputChip, 'groceries'),
            matching: find.byIcon(Icons.clear),
          ),
        );
        await tester.pumpAndSettle();

        final tasks = container.read(taskListProvider).value!;
        final updated = tasks.singleWhere((t) => t.id == created.id);
        expect(updated.tags, ['errands']);
        expect(find.text('groceries'), findsNothing);
      });

      testWidgets('Delete asks for confirmation, then removes the task and '
          'closes the modal', (tester) async {
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
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Open'), findsOneWidget);
      });

      testWidgets('canceling the delete confirmation leaves the task', (
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
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks.where((t) => t.id == created.id), hasLength(1));
      });
    });
  });
}
