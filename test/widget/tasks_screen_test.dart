// test/widget/tasks_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

/// Builds a minimal [GoRouter] with just a `/tasks` route, so tests can
/// exercise search-query-parameter sync without pulling in the full app
/// router (and its other branches/screens).
GoRouter _buildTestRouter({String initialLocation = '/tasks'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/tasks', builder: (context, state) => const TasksScreen()),
  ],
);

Future<void> _pumpWithRouter(
  WidgetTester tester,
  GoRouter router, {
  ProviderContainer? container,
}) async {
  final app = MaterialApp.router(routerConfig: router);
  await tester.pumpWidget(
    container != null
        ? UncontrolledProviderScope(container: container, child: app)
        : ProviderScope(child: app),
  );
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

    testWidgets('adding a task via the app bar action shows it in the list', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        'Buy milk',
      );
      await tester.pump();

      // The modal stays open (no Save step to close it), so both its own
      // title field and the card behind it now show "Buy milk".
      expect(find.text('Buy milk'), findsWidgets);
    });

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
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        'Buy oat milk',
      );
      await tester.pump();

      expect(find.text('Buy oat milk'), findsWidgets);
      expect(find.text('Buy milk'), findsNothing);
    });

    testWidgets('preserves list order across adds', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container.read(taskListProvider.notifier).addTask(title: 'First');
      await container.read(taskListProvider.notifier).addTask(title: 'Second');
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

    testWidgets('typing plain text filters tasks by title '
        '(case-insensitive substring)', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), 'MILK');
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsNothing);
    });

    testWidgets('clearing the search field restores the full list', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), 'milk');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsOneWidget);
    });

    testWidgets('a #tag anywhere in the text filters to tasks with that '
        'tag', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final tagged = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .updateTask(tagged, tags: ['groceries']);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '#groceries');
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsNothing);
    });

    testWidgets('several #tags in the text combine with AND', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final both = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(both, tags: ['groceries', 'urgent']);
      final one = await notifier.addTask(title: 'Buy eggs');
      await notifier.updateTask(one, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '#groceries #urgent');
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Buy eggs'), findsNothing);
    });

    testWidgets('#!tag excludes tasks with that tag', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final tagged = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .updateTask(tagged, tags: ['urgent']);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '#!urgent');
      await tester.pump();

      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('Walk the dog'), findsOneWidget);
    });

    testWidgets('/opened filters to tasks that are not closed', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      final closed = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await container
          .read(taskListProvider.notifier)
          .updateTask(closed, closed: true);
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '/opened');
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsNothing);
    });

    testWidgets('/!opened filters to closed tasks', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      final closed = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await container
          .read(taskListProvider.notifier)
          .updateTask(closed, closed: true);
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '/!opened');
      await tester.pump();

      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('Walk the dog'), findsOneWidget);
    });

    testWidgets('a /word that is not "opened" is left as plain search '
        'text', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: '/other task');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '/other');
      await tester.pump();

      expect(find.text('/other task'), findsOneWidget);
    });

    testWidgets('tapping a rendered tag token toggles it between '
        'include and exclude', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final tagged = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .updateTask(tagged, tags: ['urgent']);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Sell couch');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '#urgent');
      await tester.pump();
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Sell couch'), findsNothing);

      // Tap near the start of the field's text (not its center — the
      // field is much wider than "#urgent", and text is left-aligned
      // after the prefix icon, so a center tap would land past the end
      // of the text in empty space). If this offset doesn't land on the
      // token in practice, use `debugDumpRenderTree()` or nudge the x
      // value — the field's prefix icon plus content padding puts text
      // start a little past the field's own left edge.
      final fieldTopLeft = tester.getTopLeft(find.byType(TextField));
      await tester.tapAt(fieldTopLeft + const Offset(45, 24));
      await tester.pump();

      expect(find.byType(TasksScreen), findsOneWidget); // still mounted
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '#!urgent');
      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('Sell couch'), findsOneWidget);
    });

    testWidgets("backspacing through a tag token's characters removes "
        'it and un-filters', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final tagged = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .updateTask(tagged, tags: ['groceries']);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '#groceries');
      await tester.pump();
      expect(find.text('Walk the dog'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('Walk the dog'), findsOneWidget);
    });

    testWidgets("the field is seeded from the route's q query parameter, "
        'verbatim', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final tagged = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .updateTask(tagged, tags: ['groceries']);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Walk the dog');
      final router = _buildTestRouter(initialLocation: '/tasks?q=%23groceries');

      await _pumpWithRouter(tester, router, container: container);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '#groceries');
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsNothing);
    });

    testWidgets('typing updates the q query parameter in the address '
        'bar to the raw text, verbatim', (tester) async {
      final router = _buildTestRouter();
      await _pumpWithRouter(tester, router);

      await tester.enterText(find.byType(TextField), 'Buy #milk');
      await tester.pump();

      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['q'],
        'Buy #milk',
      );
    });

    testWidgets('a URL with the retired tags/status params behaves like '
        'an empty query', (tester) async {
      final router = _buildTestRouter(
        initialLocation: '/tasks?tags=groceries&status=opened',
      );
      await _pumpWithRouter(tester, router);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });
  });

  group('search suggestions dropdown', () {
    testWidgets('typing "#" at the cursor shows every distinct tag '
        'across loaded tasks', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      final dog = await notifier.addTask(title: 'Walk the dog');
      await notifier.updateTask(dog, tags: ['urgent']);
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#');
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(ListTile, 'groceries'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'urgent'), findsOneWidget);
    });

    testWidgets('a partial token in the middle of the text (cursor '
        'placed right after it) still triggers suggestions', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      // "#gro" followed by " rest", cursor placed right after "#gro".
      await tester.enterText(find.byType(TextField), '#gro rest');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(ListTile, 'groceries'), findsOneWidget);
    });

    testWidgets('selecting a suggestion inserts it at the cursor, not '
        'at the end of the field', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#gro rest');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(ListTile, 'groceries'));
      await tester.pump();
      await tester.pump();

      expect(field.controller!.text, '#groceries  rest');
    });

    testWidgets('typing "/" shows "opened" as the only suggestion, only '
        'while unset', (tester) async {
      await _pump(tester);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(ListTile, 'opened'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '/opened /');
      await tester.pump();
      await tester.pump();

      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('pressing Escape closes the dropdown', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#');
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.tag), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.tag), findsNothing);
    });

    testWidgets('the dropdown closes when the search field loses focus', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#');
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.tag), findsWidgets);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.tag), findsNothing);
    });

    testWidgets('the dropdown never shows more than 4 suggestions', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      for (final tag in ['aa', 'ab', 'ac', 'ad', 'ae']) {
        final task = await notifier.addTask(title: 'Task $tag');
        await notifier.updateTask(task, tags: [tag]);
      }
      await _pump(tester, container: container);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '#a');
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.tag), findsNWidgets(4));
    });
  });
}
