// test/widget/tasks_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/tasks_screen.dart';

Future<void> _pump(WidgetTester tester, {ProviderContainer? container}) async {
  if (container != null) {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TasksScreen()),
      ),
    );
  } else {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TasksScreen())),
    );
  }
  await tester.pump();
}

void main() {
  group('TasksScreen', () {
    testWidgets('starts empty', (tester) async {
      await _pump(tester);

      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('the add-task action has an accessible tooltip', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byTooltip('Add task'), findsOneWidget);
    });

    testWidgets(
      'adding a task via the app bar action shows it in the list',
      (tester) async {
        await _pump(tester);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Buy milk');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(find.text('Buy milk'), findsOneWidget);
      },
    );

    testWidgets('tapping a task card opens it in edit mode', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pump(tester, container: container);

      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Buy oat milk');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Buy oat milk'), findsOneWidget);
      expect(find.text('Buy milk'), findsNothing);
    });

    testWidgets('preserves list order across adds', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'First');
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Second');
      await _pump(tester, container: container);

      final firstY = tester.getTopLeft(find.text('First')).dy;
      final secondY = tester.getTopLeft(find.text('Second')).dy;
      expect(firstY, lessThan(secondY));
    });

    testWidgets('toggling a card checkbox closes the task without opening '
        'the modal', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pump(tester, container: container);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      final tasks = container.read(taskListProvider).value!;
      expect(tasks.single.closed, isTrue);
    });
  });
}
