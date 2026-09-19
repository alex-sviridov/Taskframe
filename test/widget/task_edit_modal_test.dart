// test/widget/task_edit_modal_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_picker.dart';
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
    testWidgets('the title field is not autofocused when the modal opens', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final titleField = tester.widget<TextField>(
        find.byKey(const Key('task-title-field')),
      );
      expect(titleField.autofocus, isFalse);
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
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy milk',
        );
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
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy milk',
        );
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
          await tester.enterText(
            find.byKey(const Key('task-title-field')),
            'Buy milk',
          );
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
          await tester.tap(
            find.descendant(
              of: find.byType(BlockCategoryPicker),
              matching: find.byType(DropdownButtonFormField<String>),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Work').last);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('task-title-field')),
            'Buy milk',
          );
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
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy',
        );
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy milk',
        );
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
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy #groceries ',
        );
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
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy #groceries ',
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('groceries'), findsOneWidget);
      });

      testWidgets(
        'a trailing "#tag" with no space is still added when the modal is '
        'dismissed',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          await _pumpOpenButton(tester, container);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('task-title-field')),
            'Buy #groceries',
          );
          await tester.pump();

          // Dismiss by tapping the barrier, well outside the centered
          // dialog's bounds — the modal has no Save/Cancel button.
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();

          final tasks = container.read(taskListProvider).value!;
          expect(tasks, hasLength(1));
          expect(tasks.single.title, 'Buy ');
          expect(tasks.single.tags, ['groceries']);
        },
      );

      testWidgets('typing "from dd/mm/yy " strips it from the title and sets '
          'activeFrom', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy milk from 05/03/26 ',
        );
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks, hasLength(1));
        expect(tasks.single.title, 'Buy milk ');
        expect(tasks.single.activeFrom, DateTime(2026, 3, 5));
      });

      testWidgets('typing "@category " strips it from the title and sets the '
          'category', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final work = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Ship it @work ',
        );
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks, hasLength(1));
        expect(tasks.single.title, 'Ship it ');
        expect(tasks.single.categoryId, work.id);
      });

      testWidgets(
        'typing "@word " for a name that matches no category leaves it '
        'as plain text',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          await _pumpOpenButton(tester, container);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('task-title-field')),
            'Ship it @nope ',
          );
          await tester.pump();

          final tasks = container.read(taskListProvider).value!;
          expect(tasks, hasLength(1));
          expect(tasks.single.title, 'Ship it @nope ');
        },
      );

      testWidgets(
        'typing "every 1w " strips it from the title and sets repeat',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          await _pumpOpenButton(tester, container);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('task-title-field')),
            'Water plants every 1w ',
          );
          await tester.pump();

          final tasks = container.read(taskListProvider).value!;
          expect(tasks, hasLength(1));
          expect(tasks.single.title, 'Water plants ');
          expect(tasks.single.repeat, '1w');
          final numberField = tester.widget<TextField>(
            find.byKey(const Key('task-repeat-number-field')),
          );
          expect(numberField.controller?.text, '1');
          final dropdown = tester.widget<DropdownButton<String>>(
            find.byKey(const Key('task-repeat-unit-dropdown')),
          );
          expect(dropdown.value, 'w');
        },
      );

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
              .widget<TextField>(find.byKey(const Key('task-title-field')))
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
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy oat milk',
        );
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
        final titleField = tester.widget<TextField>(
          find.byKey(const Key('task-title-field')),
        );
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
        await tester.tap(
          find.descendant(
            of: find.byType(BlockCategoryPicker),
            matching: find.byType(DropdownButtonFormField<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Work').last);
        await tester.pumpAndSettle();

        final tasks = container.read(taskListProvider).value!;
        expect(
          tasks.singleWhere((t) => t.id == created.id).categoryId,
          work.id,
        );
      });

      testWidgets('shows an "Active from" field, always present', (
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

        expect(find.byKey(const Key('task-active-from-field')), findsOneWidget);
      });

      testWidgets('pre-fills the "Active from" field with an existing date', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(taskListProvider.notifier)
            .addTask(title: 'Buy milk', activeFrom: DateTime(2026, 3, 5));
        await _pumpOpenButton(tester, container, task: created);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(
          find.byKey(const Key('task-active-from-field')),
        );
        expect(field.controller?.text, '05/03/26');
      });

      testWidgets('typing a valid date into the field sets activeFrom', (
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
        await tester.enterText(
          find.byKey(const Key('task-active-from-field')),
          '05/03/26',
        );
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(
          tasks.singleWhere((t) => t.id == created.id).activeFrom,
          DateTime(2026, 3, 5),
        );
      });

      testWidgets('clearing the field removes activeFrom', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(taskListProvider.notifier)
            .addTask(title: 'Buy milk', activeFrom: DateTime(2026, 3, 5));
        await _pumpOpenButton(tester, container, task: created);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('task-active-from-clear')));
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks.singleWhere((t) => t.id == created.id).activeFrom, isNull);
      });

      testWidgets(
        'the title is grayish and italic when activeFrom is in the future',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          final future = DateTime.now().add(const Duration(days: 30));
          final created = await container
              .read(taskListProvider.notifier)
              .addTask(title: 'Buy milk', activeFrom: future);
          await _pumpOpenButton(tester, container, task: created);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          final titleField = tester.widget<TextField>(
            find.byKey(const Key('task-title-field')),
          );
          expect(titleField.style?.fontStyle, FontStyle.italic);
        },
      );

      testWidgets('shows a "Repeat" field, always present', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(taskListProvider.notifier)
            .addTask(title: 'Water plants');
        await _pumpOpenButton(tester, container, task: created);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('task-repeat-number-field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('task-repeat-unit-dropdown')),
          findsOneWidget,
        );
      });

      testWidgets(
        'the unit dropdown defaults to "week" when the task has no repeat',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          final created = await container
              .read(taskListProvider.notifier)
              .addTask(title: 'Water plants');
          await _pumpOpenButton(tester, container, task: created);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          final dropdown = tester.widget<DropdownButton<String>>(
            find.byKey(const Key('task-repeat-unit-dropdown')),
          );
          expect(dropdown.value, 'w');
        },
      );

      testWidgets(
        'pre-fills the number field and unit dropdown with an existing '
        'repeat',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          final created = await container
              .read(taskListProvider.notifier)
              .addTask(title: 'Water plants');
          await container
              .read(taskListProvider.notifier)
              .updateTask(created, repeat: '2m');
          final repeating = container
              .read(taskListProvider)
              .value!
              .singleWhere((t) => t.id == created.id);
          await _pumpOpenButton(tester, container, task: repeating);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          final numberField = tester.widget<TextField>(
            find.byKey(const Key('task-repeat-number-field')),
          );
          expect(numberField.controller?.text, '2');
          final dropdown = tester.widget<DropdownButton<String>>(
            find.byKey(const Key('task-repeat-unit-dropdown')),
          );
          expect(dropdown.value, 'm');
        },
      );

      testWidgets('typing a number with the default unit sets repeat', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(taskListProvider.notifier)
            .addTask(title: 'Water plants');
        await _pumpOpenButton(tester, container, task: created);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('task-repeat-number-field')),
          '2',
        );
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks.singleWhere((t) => t.id == created.id).repeat, '2w');
      });

      testWidgets('changing the unit dropdown updates repeat', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(taskListProvider.notifier)
            .addTask(title: 'Water plants');
        await _pumpOpenButton(tester, container, task: created);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('task-repeat-number-field')),
          '3',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('task-repeat-unit-dropdown')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Month').last);
        await tester.pumpAndSettle();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks.singleWhere((t) => t.id == created.id).repeat, '3m');
      });

      testWidgets('clearing the number field removes repeat', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(taskListProvider.notifier)
            .addTask(title: 'Water plants');
        await container
            .read(taskListProvider.notifier)
            .updateTask(created, repeat: '1w');
        final repeating = container
            .read(taskListProvider)
            .value!
            .singleWhere((t) => t.id == created.id);
        await _pumpOpenButton(tester, container, task: repeating);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('task-repeat-number-field')),
          '',
        );
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks.singleWhere((t) => t.id == created.id).repeat, isNull);
      });

      testWidgets('tapping the clear button removes repeat and resets the '
          'unit to "week"', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(taskListProvider.notifier)
            .addTask(title: 'Water plants');
        await container
            .read(taskListProvider.notifier)
            .updateTask(created, repeat: '2m');
        final repeating = container
            .read(taskListProvider)
            .value!
            .singleWhere((t) => t.id == created.id);
        await _pumpOpenButton(tester, container, task: repeating);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('task-repeat-clear')));
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        expect(tasks.singleWhere((t) => t.id == created.id).repeat, isNull);
        final numberField = tester.widget<TextField>(
          find.byKey(const Key('task-repeat-number-field')),
        );
        expect(numberField.controller?.text, isEmpty);
        final dropdown = tester.widget<DropdownButton<String>>(
          find.byKey(const Key('task-repeat-unit-dropdown')),
        );
        expect(dropdown.value, 'w');
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
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy milk #errands ',
        );
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        final updated = tasks.singleWhere((t) => t.id == created.id);
        expect(updated.title, 'Buy milk ');
        expect(updated.tags, ['errands']);
      });

      testWidgets('typing "@category " in edit mode sets the category', (
        tester,
      ) async {
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
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy milk @work ',
        );
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        final updated = tasks.singleWhere((t) => t.id == created.id);
        expect(updated.title, 'Buy milk ');
        expect(updated.categoryId, work.id);
      });

      testWidgets(
        'a trailing "@category" with no space is still applied when the '
        'modal is dismissed',
        (tester) async {
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
          await tester.enterText(
            find.byKey(const Key('task-title-field')),
            'Buy milk @work',
          );
          await tester.pump();
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();

          final tasks = container.read(taskListProvider).value!;
          final updated = tasks.singleWhere((t) => t.id == created.id);
          expect(updated.title, 'Buy milk ');
          expect(updated.categoryId, work.id);
        },
      );

      testWidgets(
        'a trailing "#tag" with no space is still added when the modal is '
        'dismissed',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          final created = await container
              .read(taskListProvider.notifier)
              .addTask(title: 'Buy milk');
          await _pumpOpenButton(tester, container, task: created);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('task-title-field')),
            'Buy milk #errands',
          );
          await tester.pump();
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();

          final tasks = container.read(taskListProvider).value!;
          final updated = tasks.singleWhere((t) => t.id == created.id);
          expect(updated.title, 'Buy milk ');
          expect(updated.tags, ['errands']);
        },
      );

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

    group('title suggestions dropdown', () {
      testWidgets('typing "#" shows every distinct tag across loaded tasks', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final notifier = container.read(taskListProvider.notifier);
        final milk = await notifier.addTask(title: 'Buy milk');
        await notifier.updateTask(milk, tags: ['groceries']);
        final dog = await notifier.addTask(title: 'Walk the dog');
        await notifier.updateTask(dog, tags: ['urgent']);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('task-title-field')), '#');
        await tester.pump();
        await tester.pump();

        expect(find.widgetWithText(ListTile, 'groceries'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'urgent'), findsOneWidget);
      });

      testWidgets('excludes tags already applied to this task', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final notifier = container.read(taskListProvider.notifier);
        final milk = await notifier.addTask(title: 'Buy milk');
        await notifier.updateTask(milk, tags: ['groceries']);
        final tagged = container
            .read(taskListProvider)
            .value!
            .singleWhere((t) => t.id == milk.id);
        await _pumpOpenButton(tester, container, task: tagged);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Buy milk #',
        );
        await tester.pump();
        await tester.pump();

        expect(find.widgetWithText(ListTile, 'groceries'), findsNothing);
      });

      testWidgets('selecting a tag suggestion completes it and adds the tag', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final notifier = container.read(taskListProvider.notifier);
        final milk = await notifier.addTask(title: 'Buy milk');
        await notifier.updateTask(milk, tags: ['groceries']);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('task-title-field')),
          'Ship it #gro',
        );
        await tester.pump();
        await tester.pump();

        await tester.tap(find.widgetWithText(ListTile, 'groceries'));
        await tester.pump();
        await tester.pump();

        final tasks = container.read(taskListProvider).value!;
        final created = tasks.singleWhere((t) => t.title == 'Ship it ');
        expect(created.tags, ['groceries']);
      });

      testWidgets('typing "@" shows every category name', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Home', colorValue: 0xFF4CAF50);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('task-title-field')), '@');
        await tester.pump();
        await tester.pump();

        expect(find.widgetWithText(ListTile, 'work'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'home'), findsOneWidget);
      });

      testWidgets(
        'selecting a category suggestion sets the category and strips '
        'the text',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          final work = await container
              .read(categoryListProvider.notifier)
              .addCategory(name: 'Work', colorValue: 0xFF2196F3);
          await _pumpOpenButton(tester, container);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('task-title-field')),
            'Ship it @wo',
          );
          await tester.pump();
          await tester.pump();

          await tester.tap(find.widgetWithText(ListTile, 'work'));
          await tester.pump();
          await tester.pump();

          final tasks = container.read(taskListProvider).value!;
          final created = tasks.singleWhere((t) => t.title == 'Ship it ');
          expect(created.categoryId, work.id);
        },
      );

      testWidgets('pressing Escape closes the dropdown', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final notifier = container.read(taskListProvider.notifier);
        final milk = await notifier.addTask(title: 'Buy milk');
        await notifier.updateTask(milk, tags: ['groceries']);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('task-title-field')), '#');
        await tester.pump();
        await tester.pump();
        expect(find.widgetWithText(ListTile, 'groceries'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();

        expect(find.widgetWithText(ListTile, 'groceries'), findsNothing);
      });

      testWidgets(
        'the dropdown appears from typing alone, with no separate focus '
        'change in between (regression: a keystroke that matches no '
        'extraction pattern must still trigger a rebuild)',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          final notifier = container.read(taskListProvider.notifier);
          final milk = await notifier.addTask(title: 'Buy milk');
          await notifier.updateTask(milk, tags: ['groceries']);
          await _pumpOpenButton(tester, container);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          // Focuses the field and types a prefix that matches no
          // extraction pattern and opens no dropdown.
          await tester.enterText(
            find.byKey(const Key('task-title-field')),
            'Ship it ',
          );
          await tester.pump();
          await tester.pump();
          expect(find.byType(ListTile), findsNothing);

          // The field is already focused now, so this second enterText
          // call types one more character with no accompanying focus
          // change (focusing an already-focused field is a no-op) —
          // exactly the steady-state typing case that must still refresh
          // the dropdown on its own.
          await tester.enterText(
            find.byKey(const Key('task-title-field')),
            'Ship it #',
          );
          await tester.pump();
          await tester.pump();

          expect(find.widgetWithText(ListTile, 'groceries'), findsOneWidget);
        },
      );
    });
  });
}
