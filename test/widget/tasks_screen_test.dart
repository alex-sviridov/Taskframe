// test/widget/tasks_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/saved_search/providers.dart';
import 'package:taskframe/features/task/data/task_repository.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/tasks_screen.dart';

/// A [TaskRepository] that serves a fixed, pre-built task list from
/// [load] — lets tests seed tasks with an explicit [Task.closedAt]
/// that the normal add/update flow (which always stamps "now") can't
/// produce.
class _PresetTaskRepository implements TaskRepository {
  new(this._tasks);

  final List<Task> _tasks;

  @override
  Future<List<Task>> load() async => _tasks;

  @override
  Future<Task> add({
    required String title,
    String? categoryId,
    DateTime? activeFrom,
  }) => throw UnimplementedError();

  @override
  Future<Task> update(
    Task task, {
    String? title,
    bool? closed,
    String? categoryId,
    List<String>? tags,
    DateTime? activeFrom,
    bool clearActiveFrom = false,
    String? repeat,
    bool clearRepeat = false,
  }) => throw UnimplementedError();

  @override
  Future<void> delete(Task task) => throw UnimplementedError();
}

/// The search field's single [RenderEditable], for computing precise
/// tap positions against a token's actual rendered character boxes
/// rather than guessing pixel offsets — the search bar's tap-to-toggle
/// hit-testing is itself geometry-based (see `_handleFieldTap` in
/// `tasks_screen.dart`), so these tests probe the same geometry.
///
/// [EditableText]'s own render object isn't a [RenderEditable] directly
/// (it's wrapped, e.g. for platform text composition), so this walks the
/// render tree the same way `_handleFieldTap`'s own
/// `_findRenderEditable` does.
RenderEditable _renderEditable(WidgetTester tester) {
  final root = tester.renderObject(find.byType(EditableText));
  RenderEditable? found;
  void visit(RenderObject child) {
    if (found != null) return;
    if (child is RenderEditable) {
      found = child;
      return;
    }
    child.visitChildren(visit);
  }

  visit(root);
  return found!;
}

/// The global-coordinate [Rect] the field renders characters
/// `start`..`end` (exclusive) within, per
/// [RenderEditable.getBoxesForSelection].
Rect _tokenRect(WidgetTester tester, int start, int end) {
  final renderEditable = _renderEditable(tester);
  final box = renderEditable
      .getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end))
      .single;
  final rect = box.toRect();
  final topLeft = renderEditable.localToGlobal(rect.topLeft);
  return topLeft & rect.size;
}

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
          matching: find.byKey(const Key('task-title-field')),
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
          matching: find.byKey(const Key('task-title-field')),
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

    testWidgets('empty query hides a task closed before today by default', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWithValue(
            _PresetTaskRepository([
              Task(id: 't1', title: 'Buy milk'),
              Task(
                id: 't2',
                title: 'Walk the dog',
                closed: true,
                closedAt: DateTime.now().subtract(const Duration(days: 2)),
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await _pump(tester, container: container);

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsNothing);
    });

    testWidgets('empty query still shows a task closed today', (tester) async {
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWithValue(
            _PresetTaskRepository([
              Task(
                id: 't1',
                title: 'Walk the dog',
                closed: true,
                closedAt: DateTime.now(),
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await _pump(tester, container: container);

      expect(find.text('Walk the dog'), findsOneWidget);
    });

    testWidgets(
      'empty query still shows a closed task with no closedAt, since its '
      'age cannot be determined',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            taskRepositoryProvider.overrideWithValue(
              _PresetTaskRepository([
                Task(id: 't1', title: 'Walk the dog', closed: true),
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        await container.read(taskListProvider.future);
        await _pump(tester, container: container);

        expect(find.text('Walk the dog'), findsOneWidget);
      },
    );

    testWidgets('/!opened shows a task closed before today', (tester) async {
      final container = ProviderContainer(
        overrides: [
          taskRepositoryProvider.overrideWithValue(
            _PresetTaskRepository([
              Task(
                id: 't1',
                title: 'Walk the dog',
                closed: true,
                closedAt: DateTime.now().subtract(const Duration(days: 2)),
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '/!opened');
      await tester.pump();

      expect(find.text('Walk the dog'), findsOneWidget);
    });

    testWidgets('/active filters to tasks that are already active', (
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
          .addTask(
            title: 'Plan trip',
            activeFrom: DateTime.now().add(const Duration(days: 30)),
          );
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '/active');
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Plan trip'), findsNothing);
    });

    testWidgets('/!active filters to tasks not yet active', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await container
          .read(taskListProvider.notifier)
          .addTask(
            title: 'Plan trip',
            activeFrom: DateTime.now().add(const Duration(days: 30)),
          );
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '/!active');
      await tester.pump();

      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('Plan trip'), findsOneWidget);
    });

    testWidgets('/opened and /active combine with AND', (tester) async {
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
      await container
          .read(taskListProvider.notifier)
          .addTask(
            title: 'Plan trip',
            activeFrom: DateTime.now().add(const Duration(days: 30)),
          );
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), '/opened /active');
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk the dog'), findsNothing);
      expect(find.text('Plan trip'), findsNothing);
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

      // Tap the actual center of the rendered "#urgent" token's glyph
      // box, computed from the field's own RenderEditable rather than a
      // guessed pixel offset — a guessed offset can silently land in the
      // field's padding instead of on the token (see the regression
      // tests below), which passes only via an unrelated hit-testing
      // bug.
      await tester.tapAt(_tokenRect(tester, 0, 7).center);
      await tester.pump();

      expect(find.byType(TasksScreen), findsOneWidget); // still mounted
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '#!urgent');
      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('Sell couch'), findsOneWidget);
    });

    testWidgets("tapping the trailing half of a token's last character "
        "still toggles it (no dead zone at the token's trailing edge)", (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField), '#urgent');
      await tester.pump();

      // The right 10% of the last character ('t', the 7th of 7) — deep
      // enough into its trailing half that a naive caret-offset check
      // (which resolves a right-half tap to the boundary *after* the
      // character, i.e. offset 7 == range.end) would wrongly reject it.
      final lastCharRect = _tokenRect(tester, 6, 7);
      final tapPosition = Offset(
        lastCharRect.left + lastCharRect.width * 0.9,
        lastCharRect.center.dy,
      );
      await tester.tapAt(tapPosition);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '#!urgent');
    });

    testWidgets('tapping the space just before a token does not toggle '
        'it (no false positive just before a token)', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField), 'buy #urgent');
      await tester.pump();

      // "buy #urgent": the space is character index 3, the token starts
      // at index 4. Tapping the right (trailing) half of that space — a
      // point visually clearly to the left of "#urgent" — resolves the
      // caret to offset 4, i.e. the token's own range.start, which a
      // naive `offset >= range.start` check would wrongly accept.
      final spaceRect = _tokenRect(tester, 3, 4);
      final tapPosition = Offset(
        spaceRect.left + spaceRect.width * 0.9,
        spaceRect.center.dy,
      );
      await tester.tapAt(tapPosition);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'buy #urgent');
    });

    testWidgets("tapping the field's empty leading padding does not "
        'toggle a token starting at offset 0', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField), '#urgent');
      await tester.pump();

      // Tap just to the left of where the first character actually
      // renders (inside the gap between the prefix icon and the text,
      // still within the field's own tappable area). Flutter clamps an
      // out-of-text tap's caret to offset 0, which a naive
      // `offset >= range.start` check (with the token starting at 0)
      // would wrongly accept.
      final firstCharRect = _tokenRect(tester, 0, 1);
      final tapPosition = Offset(
        firstCharRect.left - 5,
        firstCharRect.center.dy,
      );
      expect(
        tester.getRect(find.byType(TextField)).contains(tapPosition),
        isTrue,
        reason:
            'test setup: the padding tap must still land inside the '
            'field, or this would not exercise onTap at all',
      );
      await tester.tapAt(tapPosition);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '#urgent');
    });

    testWidgets('tapping plain free text (no token involved) leaves the '
        'query untouched', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField), 'buy milk');
      await tester.pump();

      final wordRect = _tokenRect(tester, 4, 8); // "milk"
      await tester.tapAt(wordRect.center);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'buy milk');
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

    testWidgets("search field updates when the route's q parameter changes "
        'while already mounted', (tester) async {
      final router = _buildTestRouter();
      await _pumpWithRouter(tester, router);

      router.go('/tasks?q=%23urgent');
      await tester.pumpAndSettle();

      expect(find.text('#urgent'), findsOneWidget);
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

    testWidgets('typing "/" shows "opened" and "active", each only while '
        'unset', (tester) async {
      await _pump(tester);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(ListTile, 'opened'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'active'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '/opened /');
      await tester.pump();
      await tester.pump();

      expect(find.widgetWithText(ListTile, 'opened'), findsNothing);
      expect(find.widgetWithText(ListTile, 'active'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '/opened /active /');
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

  group('filter row', () {
    testWidgets('is hidden by default', (tester) async {
      await _pump(tester);

      expect(find.text('#tag'), findsNothing);
      expect(find.text('/status'), findsNothing);
      expect(find.text('@category'), findsNothing);
    });

    testWidgets('tapping the filter toggle shows the #tag /status '
        '@category buttons', (tester) async {
      await _pump(tester);

      await tester.tap(find.byTooltip('Filters'));
      await tester.pump();

      expect(find.text('#tag'), findsOneWidget);
      expect(find.text('/status'), findsOneWidget);
      expect(find.text('@category'), findsOneWidget);
    });

    testWidgets('tapping the filter toggle again hides the row', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byTooltip('Filters'));
      await tester.pump();
      await tester.tap(find.byTooltip('Filters'));
      await tester.pump();

      expect(find.text('#tag'), findsNothing);
    });

    testWidgets('tapping the #tag button inserts "#" at the cursor and '
        'opens the tag suggestions dropdown', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      final milk = await notifier.addTask(title: 'Buy milk');
      await notifier.updateTask(milk, tags: ['groceries']);
      await _pump(tester, container: container);

      await tester.enterText(find.byType(TextField), 'buy ');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      await tester.tap(find.byTooltip('Filters'));
      await tester.pump();

      await tester.tap(find.text('#tag'));
      await tester.pump();
      await tester.pump();

      expect(field.controller!.text, 'buy #');
      expect(find.widgetWithText(ListTile, 'groceries'), findsOneWidget);
    });

    testWidgets('tapping the @category button inserts "@" mid-text with '
        'a leading space when the cursor sits right after a word', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField), 'buy milk');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();
      await tester.tap(find.byTooltip('Filters'));
      await tester.pump();

      await tester.tap(find.text('@category'));
      await tester.pump();

      expect(field.controller!.text, 'buy @ milk');
    });

    testWidgets('tapping the /status button does not insert a leading '
        'space when the cursor already sits after whitespace', (tester) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField), 'buy ');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      await tester.tap(find.byTooltip('Filters'));
      await tester.pump();

      await tester.tap(find.text('/status'));
      await tester.pump();

      expect(field.controller!.text, 'buy /');
    });

    testWidgets('the filter row stays open after tapping a filter button', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byTooltip('Filters'));
      await tester.pump();
      await tester.tap(find.text('#tag'));
      await tester.pump();

      expect(find.text('#tag'), findsOneWidget);
    });

    testWidgets('star icon is outlined for a query with no saved view', (
      tester,
    ) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), '#urgent');
      await tester.pump();

      expect(find.byIcon(Icons.star_border), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    testWidgets('tapping the star icon creates a saved view', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container.read(savedSearchListProvider.future);
      await _pump(tester, container: container);
      await tester.enterText(find.byType(TextField), '#urgent');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pump();

      final views = container.read(savedSearchListProvider).value!;
      expect(views.single.query, '#urgent');
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('tapping a filled star deletes the saved view', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container.read(savedSearchListProvider.future);
      await _pump(tester, container: container);
      await tester.enterText(find.byType(TextField), '#urgent');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.star));
      await tester.pump();

      final views = container.read(savedSearchListProvider).value!;
      expect(views, isEmpty);
      expect(find.byIcon(Icons.star_border), findsOneWidget);
    });

    testWidgets('star icon is hidden when the query is empty', (tester) async {
      await _pump(tester);

      expect(find.byIcon(Icons.star_border), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
    });
  });
}
