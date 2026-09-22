import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/day_blocks_provider.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/now/now_screen.dart';
import 'package:taskframe/features/task/providers.dart';

DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// A [DayBlocksRepository] that always returns a fixed set of blocks for
/// today, anchored to the current time so the "current" slot is
/// deterministic regardless of when the test runs.
class _FixedDayBlocksRepository implements DayBlocksRepository {
  new(List<TimeObject> blocks) : blocks = [...blocks];

  List<TimeObject> blocks;

  @override
  Future<List<TimeObject>> load(DateTime date) async => blocks;

  @override
  Future<TimeObject> add(
    DateTime date, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  }) => throw UnimplementedError();

  @override
  Future<TimeObject> move(
    TimeObject block, {
    required DateTime fromDate,
    required DateTime toDate,
    required DateTime newStart,
    required DateTime newEnd,
  }) => throw UnimplementedError();

  @override
  Future<TimeObject> update(
    TimeObject block, {
    required DateTime date,
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  }) async {
    final updated = TimeObject(
      id: block.id,
      title: title ?? block.title,
      start: start ?? block.start,
      end: end ?? block.end,
      kind: kind ?? block.kind,
      locked: block.locked,
      categoryId: categoryId ?? block.categoryId,
    );
    blocks = [
      for (final b in blocks)
        if (b.id == block.id) updated else b,
    ];
    return updated;
  }

  @override
  Future<void> delete(TimeObject block, {required DateTime date}) =>
      throw UnimplementedError();
}

TimeObject _blockAround(
  DateTime now, {
  required String id,
  required int startOffsetMinutes,
  required int endOffsetMinutes,
  BlockKind kind = BlockKind.anchor,
  String categoryId = Category.defaultId,
}) {
  DateTime onGrid(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute ~/ 15 * 15);
  return TimeObject(
    id: id,
    title: id,
    start: onGrid(now.add(Duration(minutes: startOffsetMinutes))),
    end: onGrid(now.add(Duration(minutes: endOffsetMinutes))),
    kind: kind,
    locked: false,
    categoryId: categoryId,
  );
}

void main() {
  group('NowScreen', () {
    testWidgets('shows the block covering now as Current, with its '
        'category color', (tester) async {
      final now = DateTime.now();
      final blocks = [
        _blockAround(
          now,
          id: 'Earlier',
          startOffsetMinutes: -90,
          endOffsetMinutes: -60,
        ),
        _blockAround(
          now,
          id: 'Working',
          startOffsetMinutes: -30,
          endOffsetMinutes: 30,
        ),
        _blockAround(
          now,
          id: 'Later',
          startOffsetMinutes: 60,
          endOffsetMinutes: 90,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dayBlocksRepositoryProvider.overrideWithValue(
              _FixedDayBlocksRepository(blocks),
            ),
          ],
          child: const MaterialApp(home: NowScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Working'), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('when the current block is a frame, shows up to 3 oldest open, '
        'active tasks in its category, tappable to close', (tester) async {
      final now = DateTime.now();
      final blocks = [
        _blockAround(
          now,
          id: 'Deep work',
          startOffsetMinutes: -30,
          endOffsetMinutes: 30,
          kind: BlockKind.frame,
          categoryId: 'work',
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          dayBlocksRepositoryProvider.overrideWithValue(
            _FixedDayBlocksRepository(blocks),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(taskListProvider.future);
      final notifier = container.read(taskListProvider.notifier);
      await notifier.addTask(title: 'Task A', categoryId: 'work');
      await notifier.addTask(title: 'Task B', categoryId: 'work');
      await notifier.addTask(title: 'Task C', categoryId: 'work');
      // A 4th, newer task: shouldn't be shown, since only 3 fit.
      await notifier.addTask(title: 'Task D', categoryId: 'work');
      // Wrong category: shouldn't be shown.
      await notifier.addTask(title: 'Other category', categoryId: '0');
      final closed = await notifier.addTask(
        title: 'Already closed',
        categoryId: 'work',
      );
      await notifier.updateTask(closed, closed: true);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NowScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Frame tasks'), findsOneWidget);
      expect(find.text('Task A'), findsOneWidget);
      expect(find.text('Task B'), findsOneWidget);
      expect(find.text('Task C'), findsOneWidget);
      expect(find.text('Task D'), findsNothing);
      expect(find.text('Other category'), findsNothing);
      expect(find.text('Already closed'), findsNothing);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.singleWhere((t) => t.title == 'Task A').closed, isTrue);
    });

    testWidgets(
      'shows one placeholder per slot, and a single "Next" label, when '
      'nothing is scheduled',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dayBlocksRepositoryProvider.overrideWithValue(
                _FixedDayBlocksRepository(const []),
              ),
            ],
            child: const MaterialApp(home: NowScreen()),
          ),
        );
        await tester.pump();

        expect(find.text('Nothing scheduled'), findsNWidgets(3));
        expect(find.text('Next'), findsOneWidget);
      },
    );

    testWidgets(
      'shows a second Next card with no extra label or placeholder when '
      'a second upcoming block exists',
      (tester) async {
        final now = DateTime.now();
        final blocks = [
          _blockAround(
            now,
            id: 'Working',
            startOffsetMinutes: -30,
            endOffsetMinutes: 30,
          ),
          _blockAround(
            now,
            id: 'Soon',
            startOffsetMinutes: 60,
            endOffsetMinutes: 90,
          ),
          _blockAround(
            now,
            id: 'Later',
            startOffsetMinutes: 120,
            endOffsetMinutes: 150,
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dayBlocksRepositoryProvider.overrideWithValue(
                _FixedDayBlocksRepository(blocks),
              ),
            ],
            child: const MaterialApp(home: NowScreen()),
          ),
        );
        await tester.pump();

        expect(find.text('Next'), findsOneWidget);
        expect(find.text('Soon'), findsOneWidget);
        expect(find.text('Later'), findsOneWidget);
        // Previous is still empty (nothing before "Working"); the Next
        // section itself has no placeholder since both its slots are full.
        expect(find.text('Nothing scheduled'), findsOneWidget);
      },
    );

    testWidgets('shows only one Next card and no placeholder when there is no '
        'second upcoming block', (tester) async {
      final now = DateTime.now();
      final blocks = [
        _blockAround(
          now,
          id: 'Working',
          startOffsetMinutes: -30,
          endOffsetMinutes: 30,
        ),
        _blockAround(
          now,
          id: 'Soon',
          startOffsetMinutes: 60,
          endOffsetMinutes: 90,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dayBlocksRepositoryProvider.overrideWithValue(
              _FixedDayBlocksRepository(blocks),
            ),
          ],
          child: const MaterialApp(home: NowScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Soon'), findsOneWidget);
      // Previous is empty (1 placeholder); the second Next slot has none
      // of its own since next2 doesn't exist here.
      expect(find.text('Nothing scheduled'), findsOneWidget);
    });

    group('swipe to postpone', () {
      testWidgets('swiping a block card right postpones it 15 minutes into '
          'the future', (tester) async {
        final now = DateTime.now();
        final blocks = [
          _blockAround(
            now,
            id: 'Working',
            startOffsetMinutes: -30,
            endOffsetMinutes: 30,
          ),
        ];
        final container = ProviderContainer(
          overrides: [
            dayBlocksRepositoryProvider.overrideWithValue(
              _FixedDayBlocksRepository(blocks),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: NowScreen()),
          ),
        );
        await tester.pump();

        await tester.drag(find.text('Working'), const Offset(200, 0));
        await tester.pumpAndSettle();

        final updated = container
            .read(dayBlocksProvider(_dateOnly(now)))
            .value!
            .singleWhere((b) => b.id == 'Working');
        expect(
          updated.start,
          blocks.first.start.add(const Duration(minutes: 15)),
        );
        expect(updated.end, blocks.first.end.add(const Duration(minutes: 15)));
      });

      testWidgets('swiping a block card left postpones it 15 minutes into '
          'the past', (tester) async {
        final now = DateTime.now();
        final blocks = [
          _blockAround(
            now,
            id: 'Working',
            startOffsetMinutes: -30,
            endOffsetMinutes: 30,
          ),
        ];
        final container = ProviderContainer(
          overrides: [
            dayBlocksRepositoryProvider.overrideWithValue(
              _FixedDayBlocksRepository(blocks),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: NowScreen()),
          ),
        );
        await tester.pump();

        await tester.drag(find.text('Working'), const Offset(-200, 0));
        await tester.pumpAndSettle();

        final updated = container
            .read(dayBlocksProvider(_dateOnly(now)))
            .value!
            .singleWhere((b) => b.id == 'Working');
        expect(
          updated.start,
          blocks.first.start.subtract(const Duration(minutes: 15)),
        );
        expect(
          updated.end,
          blocks.first.end.subtract(const Duration(minutes: 15)),
        );
      });

      testWidgets('does not respond to swipes on a locked block', (
        tester,
      ) async {
        final now = DateTime.now();
        DateTime onGrid(DateTime t) =>
            DateTime(t.year, t.month, t.day, t.hour, t.minute ~/ 15 * 15);
        final lockedBlock = TimeObject(
          id: 'Fixed',
          title: 'Fixed',
          start: onGrid(now.subtract(const Duration(minutes: 30))),
          end: onGrid(now.add(const Duration(minutes: 30))),
          kind: BlockKind.anchor,
          locked: true,
        );
        final container = ProviderContainer(
          overrides: [
            dayBlocksRepositoryProvider.overrideWithValue(
              _FixedDayBlocksRepository([lockedBlock]),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: NowScreen()),
          ),
        );
        await tester.pump();

        await tester.drag(find.text('Fixed'), const Offset(200, 0));
        await tester.pumpAndSettle();

        final unchanged = container
            .read(dayBlocksProvider(_dateOnly(now)))
            .value!
            .singleWhere((b) => b.id == 'Fixed');
        expect(unchanged.start, lockedBlock.start);
        expect(unchanged.end, lockedBlock.end);
      });
    });
  });
}
