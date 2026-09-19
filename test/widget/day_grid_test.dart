import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/day/day_blocks_provider.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_schedule_block_actions.dart';
import 'package:taskframe/features/day/day_schedule_controller.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/draft_state_provider.dart';
import 'package:taskframe/features/day/drag_state_provider.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/resize_state_provider.dart';
import 'package:taskframe/features/day/widgets/block_view.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
import 'package:taskframe/features/day/widgets/draggable_block.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);
const _slotHeight = 16.0;
final _date = DateTime(2026, 9, 9);

typedef _CreatedBlock = ({DateTime start, DateTime end, BlockKind kind});

Future<void> _pump(
  WidgetTester tester,
  List<TimeObject> blocks, {
  GestureDragStartCallback? onSwipeStart,
  GestureDragUpdateCallback? onSwipeUpdate,
  GestureDragEndCallback? onSwipeEnd,
  void Function({
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
  })?
  onCreateBlock,
  ProviderContainer? container,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container ?? ProviderContainer(),
    child: MaterialApp(
      home: Scaffold(
        body: DayGrid(
          key: scheduleGridKeyFor(DayColumn(_date)),
          date: _date,
          column: DayColumn(_date),
          controller: const DayScheduleController(),
          actions: dayScheduleBlockActions,
          blocks: blocks,
          settings: _settings,
          slotHeight: _slotHeight,
          onSwipeStart: onSwipeStart,
          onSwipeUpdate: onSwipeUpdate,
          onSwipeEnd: onSwipeEnd,
          onCreateBlock:
              onCreateBlock ??
              ({required start, required end, required kind}) {},
        ),
      ),
    ),
  ),
);

final _workBlock = TimeObject(
  id: '1',
  title: 'Work',
  start: DateTime(2026, 9, 9, 9),
  end: DateTime(2026, 9, 9, 13),
  kind: BlockKind.frame,
  locked: false,
);

/// Clicks at [position] with a mouse pointer — no movement, so it resolves
/// as a plain tap rather than the vertical-drag recognizer racing it in the
/// same arena.
Future<void> _clickAt(WidgetTester tester, Offset position) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.up();
  await tester.pump();
}

/// Starts a touch drag at [position] within a single-column `_pump`ed grid,
/// waiting out the long-press timeout before the first move so the
/// gesture arena has resolved in favor of the long-press recognizer.
Future<TestGesture> _startTouchDrag(
  WidgetTester tester,
  Offset position,
) async {
  final gesture = await tester.startGesture(position);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return gesture;
}

void main() {
  group('resizeEdgeForLocalY', () {
    test("picks the start edge above the block's vertical midpoint", () {
      expect(resizeEdgeForLocalY(localY: 0, blockHeight: 40), ResizeEdge.start);
      expect(
        resizeEdgeForLocalY(localY: 19, blockHeight: 40),
        ResizeEdge.start,
      );
    });

    test("picks the end edge at or below the block's vertical midpoint", () {
      expect(resizeEdgeForLocalY(localY: 20, blockHeight: 40), ResizeEdge.end);
      expect(resizeEdgeForLocalY(localY: 40, blockHeight: 40), ResizeEdge.end);
    });
  });

  group('resizeBleedForBlocks', () {
    TimeObject block(String id, int startHour, int endHour) => TimeObject(
      id: id,
      title: id,
      start: DateTime(2026, 9, 9, startHour),
      end: DateTime(2026, 9, 9, endHour),
      kind: BlockKind.anchor,
      locked: false,
    );

    double offsetFor(DateTime time) =>
        (time.hour * 60 + time.minute).toDouble();

    test('a block with no neighbors gets the full bleed on both sides', () {
      final bleed = resizeBleedForBlocks(
        blocks: [block('a', 9, 10)],
        offsetFor: offsetFor,
        maxBleed: 9,
      );

      expect(bleed['a'], (top: 9.0, bottom: 9.0));
    });

    test('a block with a wide gap to its neighbors gets the full bleed', () {
      final bleed = resizeBleedForBlocks(
        blocks: [block('a', 8, 9), block('b', 10, 11), block('c', 12, 13)],
        offsetFor: offsetFor,
        maxBleed: 9,
      );

      expect(bleed['b'], (top: 9.0, bottom: 9.0));
    });

    test('a block with a narrow gap gets clamped to half the gap', () {
      // 'a' ends at 9:15, 'b' starts at 9:30: a 15min (15px) gap, half of
      // which (7.5) is less than maxBleed (9).
      final bleed = resizeBleedForBlocks(
        blocks: [
          TimeObject(
            id: 'a',
            title: 'a',
            start: DateTime(2026, 9, 9, 9),
            end: DateTime(2026, 9, 9, 9, 15),
            kind: BlockKind.anchor,
            locked: false,
          ),
          TimeObject(
            id: 'b',
            title: 'b',
            start: DateTime(2026, 9, 9, 9, 30),
            end: DateTime(2026, 9, 9, 9, 45),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
        offsetFor: offsetFor,
        maxBleed: 9,
      );

      expect(bleed['a']!.bottom, 7.5);
      expect(bleed['b']!.top, 7.5);
    });

    test('back-to-back blocks (zero gap) get zero bleed on that side', () {
      final bleed = resizeBleedForBlocks(
        blocks: [block('a', 9, 10), block('b', 10, 11)],
        offsetFor: offsetFor,
        maxBleed: 9,
      );

      expect(bleed['a'], (top: 9.0, bottom: 0.0));
      expect(bleed['b'], (top: 0.0, bottom: 9.0));
    });

    test('is unaffected by the order blocks are passed in', () {
      final forward = resizeBleedForBlocks(
        blocks: [block('a', 9, 10), block('b', 10, 11)],
        offsetFor: offsetFor,
        maxBleed: 9,
      );
      final reversed = resizeBleedForBlocks(
        blocks: [block('b', 10, 11), block('a', 9, 10)],
        offsetFor: offsetFor,
        maxBleed: 9,
      );

      expect(reversed, forward);
    });
  });

  group('DayGrid', () {
    testWidgets('renders every block title', (tester) async {
      await _pump(tester, [
        TimeObject(
          id: '1',
          title: 'Breakfast',
          start: DateTime(2026, 9, 9, 7),
          end: DateTime(2026, 9, 9, 7, 30),
          kind: BlockKind.anchor,
          locked: false,
        ),
        TimeObject(
          id: '2',
          title: 'Work',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 13),
          kind: BlockKind.frame,
          locked: false,
        ),
      ]);

      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets("passes each block's resolved category to its BlockView", (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      final work = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3);
      await _pump(tester, [
        TimeObject(
          id: '1',
          title: 'Work',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 13),
          kind: BlockKind.anchor,
          locked: false,
          categoryId: work.id,
        ),
      ], container: container);

      final blockView = tester.widget<BlockView>(find.byType(BlockView));
      expect(blockView.category?.id, work.id);
    });

    testWidgets("prefixes a block's title overlay with its category's "
        'emoji', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      final work = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      await _pump(tester, [
        TimeObject(
          id: '1',
          title: 'Work',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 13),
          kind: BlockKind.anchor,
          locked: false,
          categoryId: work.id,
        ),
      ], container: container);

      expect(find.text('💼 Work'), findsOneWidget);
    });

    testWidgets(
      'shows every title for a run of adjacent (zero-gap) short blocks, '
      'even at the minimum slot height '
      "(regression: a short block's title could be painted over by the "
      "next block's own box)",
      (tester) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: ProviderContainer(),
            child: MaterialApp(
              home: Scaffold(
                body: DayGrid(
                  date: _date,
                  column: DayColumn(_date),
                  controller: const DayScheduleController(),
                  actions: dayScheduleBlockActions,
                  blocks: [
                    TimeObject(
                      id: 'a',
                      title: 'Fifteen',
                      start: DateTime(2026, 9, 9, 9),
                      end: DateTime(2026, 9, 9, 9, 15),
                      kind: BlockKind.anchor,
                      locked: false,
                    ),
                    TimeObject(
                      id: 'b',
                      title: 'Thirty',
                      start: DateTime(2026, 9, 9, 9, 15),
                      end: DateTime(2026, 9, 9, 9, 45),
                      kind: BlockKind.frame,
                      locked: false,
                    ),
                  ],
                  settings: _settings,
                  // The real app's minimum slot height, where a 15-minute
                  // block is only 8px tall — far shorter than one text
                  // line.
                  slotHeight: 8,
                  onCreateBlock: ({
                    required start,
                    required end,
                    required kind,
                  }) {},
                ),
              ),
            ),
          ),
        );

        expect(find.text('Fifteen'), findsOneWidget);
        expect(find.text('Thirty'), findsOneWidget);
      },
    );

    testWidgets(
      "gives a block's title overlay a fixed, one-line-tall box regardless "
      "of the block's own true (possibly tiny) duration "
      "(regression: Flutter web clips a Positioned child's paint to its "
      "own box, so a box sized to the block's true 8px height clipped the "
      'title to nothing rather than letting it overflow)',
      (tester) async {
        final tiny = TimeObject(
          id: '1',
          title: 'Tiny',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 9, 15),
          kind: BlockKind.anchor,
          locked: false,
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: ProviderContainer(),
            child: MaterialApp(
              home: Scaffold(
                body: DayGrid(
                  date: _date,
                  column: DayColumn(_date),
                  controller: const DayScheduleController(),
                  actions: dayScheduleBlockActions,
                  blocks: [tiny],
                  settings: _settings,
                  slotHeight: 8,
                  onCreateBlock: ({
                    required start,
                    required end,
                    required kind,
                  }) {},
                ),
              ),
            ),
          ),
        );

        final titleBox = tester.widget<Positioned>(
          find.byKey(const ValueKey('day-grid-block-title-1')),
        );
        // 15 minutes at slotHeight 8 is only 8px — the title box must be
        // taller than the block's own true height.
        expect(titleBox.height, greaterThan(8));
      },
    );

    testWidgets("centers a too-short block's title box on the block's own true "
        'vertical midpoint, rather than pinning it to the top', (tester) async {
      final tiny = TimeObject(
        id: '1',
        title: 'Tiny',
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 9, 15),
        kind: BlockKind.anchor,
        locked: false,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: ProviderContainer(),
          child: MaterialApp(
            home: Scaffold(
              body: DayGrid(
                date: _date,
                column: DayColumn(_date),
                controller: const DayScheduleController(),
                actions: dayScheduleBlockActions,
                blocks: [tiny],
                settings: _settings,
                slotHeight: 8,
                onCreateBlock: ({
                  required start,
                  required end,
                  required kind,
                }) {},
              ),
            ),
          ),
        ),
      );

      final titleBox = tester.widget<Positioned>(
        find.byKey(const ValueKey('day-grid-block-title-1')),
      );
      // 9:00 is 3 hours (12 slots) after the 6:00 day start = 96px; the
      // block spans 96-104 (one 15-min slot at slotHeight 8), so its
      // true vertical center is 100.
      expect(titleBox.top! + titleBox.height! / 2, 100);
    });

    testWidgets(
      "does not shift a tall block's title box away from its top edge",
      (tester) async {
        await _pump(tester, [_workBlock]);

        final titleBox = tester.widget<Positioned>(
          find.byKey(const ValueKey('day-grid-block-title-1')),
        );
        expect(titleBox.top, 12 * _slotHeight);
      },
    );

    group('drag/resize preview titles', () {
      testWidgets(
        "shows a too-short dragged block's title during the drag, styled "
        'the same way as the static grid',
        (tester) async {
          final tiny = TimeObject(
            id: '1',
            title: 'Tiny',
            start: DateTime(2026, 9, 9, 9),
            end: DateTime(2026, 9, 9, 9, 15),
            kind: BlockKind.anchor,
            locked: false,
          );
          final container = ProviderContainer();
          addTearDown(container.dispose);
          container
              .read(dragStateProvider.notifier)
              .start(
                block: tiny,
                originalColumn: DayColumn(_date),
                controller: const DayScheduleController(),
                pointerGlobalPosition: Offset.zero,
              );

          await _pump(tester, [tiny], container: container);

          // The real block's own title is suppressed for the duration of
          // the drag (see `hiddenBlockId`), so this can only be the
          // landzone preview's title.
          expect(find.text('Tiny'), findsOneWidget);

          // Regression: the landzone preview used to draw its title
          // inline in a box sized to the dragged block's own true (here
          // 8px) height, which Flutter web clips to nothing — same bug
          // as the static grid, just never fixed here too.
          final titleBox = tester.widget<Positioned>(
            find.byKey(const Key('day-grid-landzone-title')),
          );
          expect(titleBox.height, greaterThan(8));
        },
      );

      testWidgets("shows a too-short resized block's title during the resize, "
          'styled the same way as the static grid', (tester) async {
        final tiny = TimeObject(
          id: '1',
          title: 'Tiny',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 9, 15),
          kind: BlockKind.anchor,
          locked: false,
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(resizeStateProvider.notifier)
            .start(
              block: tiny,
              column: DayColumn(_date),
              controller: const DayScheduleController(),
              edge: ResizeEdge.end,
            );

        await _pump(tester, [tiny], container: container);

        // The real block's own title is suppressed for the duration of
        // the resize (see `hiddenBlockId`), so this can only be the
        // resize-draft preview's title.
        expect(find.text('Tiny'), findsOneWidget);

        final titleBox = tester.widget<Positioned>(
          find.byKey(const Key('day-grid-resize-draft-title')),
        );
        expect(titleBox.height, greaterThan(8));
      });
    });

    testWidgets(
      'paints every block title after (on top of) every block box, so a '
      'title is never covered by a sibling box',
      (tester) async {
        await _pump(tester, [
          TimeObject(
            id: 'a',
            title: 'A',
            start: DateTime(2026, 9, 9, 9),
            end: DateTime(2026, 9, 9, 9, 15),
            kind: BlockKind.anchor,
            locked: false,
          ),
          TimeObject(
            id: 'b',
            title: 'B',
            start: DateTime(2026, 9, 9, 9, 15),
            end: DateTime(2026, 9, 9, 9, 30),
            kind: BlockKind.frame,
            locked: false,
          ),
        ]);

        final stack = tester.widget<Stack>(find.byType(Stack).first);
        int indexOfKey(String key) =>
            stack.children.indexWhere((w) => w.key == ValueKey(key));

        final lastBoxIndex = [
          indexOfKey('day-grid-block-position-a'),
          indexOfKey('day-grid-block-position-b'),
        ].reduce((a, b) => a > b ? a : b);
        final firstTitleIndex = [
          indexOfKey('day-grid-block-title-a'),
          indexOfKey('day-grid-block-title-b'),
        ].reduce((a, b) => a < b ? a : b);

        expect(lastBoxIndex, greaterThanOrEqualTo(0));
        expect(firstTitleIndex, greaterThan(lastBoxIndex));
      },
    );

    testWidgets('positions a block using its offset from day start', (
      tester,
    ) async {
      await _pump(tester, [
        TimeObject(
          id: '1',
          title: 'Work',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 13),
          kind: BlockKind.frame,
          locked: false,
        ),
      ]);

      final positioned = tester.widget<Positioned>(
        find.byKey(const ValueKey('day-grid-block-position-1')),
      );

      // This Positioned is enlarged by `DraggableBlock.hitBleed` (9px) on
      // each side so the block's resize zones have room to bleed past its
      // true edges; the block itself insets its visual content back in.
      const hitBleed = 9.0;
      // 9:00 is 3 hours (12 slots) after the 6:00 day start.
      expect(positioned.top, 12 * _slotHeight - hitBleed);
      // A 4-hour block spans 16 slots.
      expect(positioned.height, 16 * _slotHeight + hitBleed * 2);
    });

    testWidgets('sizes the grid to span day-start through day-end', (
      tester,
    ) async {
      await _pump(tester, []);

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);

      // 6:00 to 23:00 is 17 hours = 68 slots.
      expect(sizedBox.height, 68 * _slotHeight);
    });

    testWidgets('uses whatever slotHeight it is given', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: ProviderContainer(),
          child: MaterialApp(
            home: Scaffold(
              body: DayGrid(
                date: _date,
                column: DayColumn(_date),
                controller: const DayScheduleController(),
                actions: dayScheduleBlockActions,
                blocks: const [],
                settings: _settings,
                slotHeight: 8,
                onCreateBlock: ({
                  required start,
                  required end,
                  required kind,
                }) {},
              ),
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);

      expect(sizedBox.height, 68 * 8.0);
    });

    testWidgets('positions a block flush left when hour labels are hidden', (
      tester,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: ProviderContainer(),
          child: MaterialApp(
            home: Scaffold(
              body: DayGrid(
                date: _date,
                column: DayColumn(_date),
                controller: const DayScheduleController(),
                actions: dayScheduleBlockActions,
                blocks: [_workBlock],
                settings: _settings,
                slotHeight: _slotHeight,
                showHourLabels: false,
                onCreateBlock: ({
                  required start,
                  required end,
                  required kind,
                }) {},
              ),
            ),
          ),
        ),
      );

      final positioned = tester.widget<Positioned>(
        find.byKey(const ValueKey('day-grid-block-position-1')),
      );

      expect(positioned.left, 4);
    });

    testWidgets('a horizontal drag on free space is forwarded to the caller', (
      tester,
    ) async {
      var started = false;
      var ended = false;
      await _pump(
        tester,
        [_workBlock],
        onSwipeStart: (_) => started = true,
        onSwipeEnd: (_) => ended = true,
      );

      // Work spans y 192-448; 500 is free space below it.
      await tester.flingFrom(
        const Offset(400, 500),
        const Offset(-300, 0),
        1000,
      );

      expect(started, isTrue);
      expect(ended, isTrue);
    });

    testWidgets('a fling starting on a block is not forwarded', (tester) async {
      var called = false;
      await _pump(tester, [_workBlock], onSwipeStart: (_) => called = true);

      // 300 is inside Work's y range (192-448).
      await tester.flingFrom(
        const Offset(400, 300),
        const Offset(-300, 0),
        1000,
      );

      expect(called, isFalse);
    });

    group('draft', () {
      testWidgets('clicking free space shows both create buttons', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, []);

        // y 192 is 9:00, well within the empty grid.
        await _clickAt(tester, const Offset(200, 192));

        expect(find.bySemanticsLabel('Create Event'), findsOneWidget);
        expect(find.bySemanticsLabel('Create Frame'), findsOneWidget);
        semantics.dispose();
      });

      testWidgets('long-pressing free space shows both create buttons', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, []);

        await tester.longPressAt(const Offset(200, 192));
        await tester.pump();

        expect(find.bySemanticsLabel('Create Event'), findsOneWidget);
        expect(find.bySemanticsLabel('Create Frame'), findsOneWidget);
        semantics.dispose();
      });

      testWidgets('tapping Create Event creates a 30-minute anchor block', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        _CreatedBlock? created;
        await _pump(
          tester,
          [],
          onCreateBlock: ({required start, required end, required kind}) {
            created = (start: start, end: end, kind: kind);
          },
        );
        await _clickAt(tester, const Offset(200, 192));

        await tester.tap(find.bySemanticsLabel('Create Event'));
        await tester.pump();

        expect(created, isNotNull);
        expect(created!.start, DateTime(2026, 9, 9, 9));
        expect(created!.end, DateTime(2026, 9, 9, 9, 30));
        expect(created!.kind, BlockKind.anchor);
        semantics.dispose();
      });

      testWidgets('tapping Create Frame creates a frame block', (tester) async {
        final semantics = tester.ensureSemantics();
        _CreatedBlock? created;
        await _pump(
          tester,
          [],
          onCreateBlock: ({required start, required end, required kind}) {
            created = (start: start, end: end, kind: kind);
          },
        );
        await _clickAt(tester, const Offset(200, 192));

        await tester.tap(find.bySemanticsLabel('Create Frame'));
        await tester.pump();

        expect(created!.kind, BlockKind.frame);
        semantics.dispose();
      });

      testWidgets(
        'shrinks the new block to 15 minutes when the next slot is taken',
        (tester) async {
          final semantics = tester.ensureSemantics();
          _CreatedBlock? created;
          final nextSlotBlock = TimeObject(
            id: '2',
            title: 'Busy',
            start: DateTime(2026, 9, 9, 9, 15),
            end: DateTime(2026, 9, 9, 9, 30),
            kind: BlockKind.anchor,
            locked: false,
          );
          await _pump(
            tester,
            [nextSlotBlock],
            onCreateBlock: ({required start, required end, required kind}) {
              created = (start: start, end: end, kind: kind);
            },
          );

          await _clickAt(tester, const Offset(200, 192));
          await tester.tap(find.bySemanticsLabel('Create Event'));
          await tester.pump();

          expect(created!.end, DateTime(2026, 9, 9, 9, 15));
          semantics.dispose();
        },
      );

      testWidgets('clicking elsewhere opens a new draft there instead, '
          'without creating a block', (tester) async {
        final semantics = tester.ensureSemantics();
        var called = false;
        await _pump(
          tester,
          [],
          onCreateBlock: ({required start, required end, required kind}) {
            called = true;
          },
        );
        await _clickAt(tester, const Offset(200, 192));
        expect(find.bySemanticsLabel('Create Event'), findsOneWidget);

        // A click elsewhere on free space opens a new draft there,
        // replacing the first one — still without committing a block.
        await _clickAt(tester, const Offset(200, 400));

        expect(find.bySemanticsLabel('Create Event'), findsOneWidget);
        expect(called, isFalse);
        semantics.dispose();
      });

      testWidgets(
        'dragging vertically before releasing sizes the draft to the drag',
        (tester) async {
          _CreatedBlock? created;
          await _pump(
            tester,
            [],
            onCreateBlock: ({required start, required end, required kind}) {
              created = (start: start, end: end, kind: kind);
            },
          );

          // y 192 is 9:00; dragging down 4 slots (64px) should size the
          // draft to 9:00-10:00 instead of the default 9:00-9:30.
          final gesture = await tester.startGesture(
            const Offset(200, 192),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 64));
          await tester.pump();
          await gesture.up();
          await tester.pump();

          final semantics = tester.ensureSemantics();
          await tester.tap(find.bySemanticsLabel('Create Event'));
          await tester.pump();

          expect(created!.start, DateTime(2026, 9, 9, 9));
          expect(created!.end, DateTime(2026, 9, 9, 10));
          semantics.dispose();
        },
      );

      testWidgets(
        'dragging upward extends the draft to start earlier, keeping the '
        'drag origin as its end',
        (tester) async {
          _CreatedBlock? created;
          await _pump(
            tester,
            [],
            onCreateBlock: ({required start, required end, required kind}) {
              created = (start: start, end: end, kind: kind);
            },
          );

          // y 192 is 9:00; dragging up 2 slots (32px) should size the draft
          // to 8:30-9:00.
          final gesture = await tester.startGesture(
            const Offset(200, 192),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, -32));
          await tester.pump();
          await gesture.up();
          await tester.pump();

          final semantics = tester.ensureSemantics();
          await tester.tap(find.bySemanticsLabel('Create Event'));
          await tester.pump();

          expect(created!.start, DateTime(2026, 9, 9, 8, 30));
          expect(created!.end, DateTime(2026, 9, 9, 9));
          semantics.dispose();
        },
      );

      testWidgets(
        'a touch long-press followed by a drag sizes the draft the same '
        'way as the mouse',
        (tester) async {
          _CreatedBlock? created;
          await _pump(
            tester,
            [],
            onCreateBlock: ({required start, required end, required kind}) {
              created = (start: start, end: end, kind: kind);
            },
          );

          final gesture = await _startTouchDrag(tester, const Offset(200, 192));
          await gesture.moveBy(const Offset(0, 64));
          await tester.pump();
          await gesture.up();
          await tester.pump();

          final semantics = tester.ensureSemantics();
          await tester.tap(find.bySemanticsLabel('Create Event'));
          await tester.pump();

          expect(created!.start, DateTime(2026, 9, 9, 9));
          expect(created!.end, DateTime(2026, 9, 9, 10));
          semantics.dispose();
        },
      );
    });

    group('draft — cross-column', () {
      testWidgets(
        'opening a draft on one column dismisses one open on another',
        (tester) async {
          final container = ProviderContainer();
          addTearDown(container.dispose);
          final dateA = DateTime(2026, 9, 9);
          final dateB = DateTime(2026, 9, 10);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: Scaffold(
                  body: Row(
                    children: [
                      Expanded(
                        child: DayGrid(
                          date: dateA,
                          column: DayColumn(dateA),
                          controller: const DayScheduleController(),
                          actions: dayScheduleBlockActions,
                          blocks: const [],
                          settings: _settings,
                          slotHeight: _slotHeight,
                          onCreateBlock: ({
                            required start,
                            required end,
                            required kind,
                          }) {},
                        ),
                      ),
                      Expanded(
                        child: DayGrid(
                          date: dateB,
                          column: DayColumn(dateB),
                          controller: const DayScheduleController(),
                          actions: dayScheduleBlockActions,
                          blocks: const [],
                          settings: _settings,
                          slotHeight: _slotHeight,
                          onCreateBlock: ({
                            required start,
                            required end,
                            required kind,
                          }) {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          final semantics = tester.ensureSemantics();
          await _clickAt(tester, const Offset(100, 192));
          expect(find.bySemanticsLabel('Create Event'), findsOneWidget);

          await _clickAt(tester, const Offset(500, 192));

          // Still exactly one draft overall — the first one is gone, not
          // just hidden behind a second.
          expect(find.bySemanticsLabel('Create Event'), findsOneWidget);
          expect(container.read(draftStateProvider)!.column, DayColumn(dateB));
          semantics.dispose();
        },
      );
    });

    group('draft — cursor', () {
      testWidgets(
        'shows a resize cursor while a mouse drag is sizing a new draft, '
        'reverting once released',
        (tester) async {
          await _pump(tester, []);

          final gesture = await tester.startGesture(
            const Offset(200, 192),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 32));
          await tester.pump();

          final region = tester.widget<MouseRegion>(
            find.byKey(const Key('day-grid-background-cursor')),
          );
          expect(region.cursor, SystemMouseCursors.resizeRow);

          await gesture.up();
          await tester.pump();

          final regionAfter = tester.widget<MouseRegion>(
            find.byKey(const Key('day-grid-background-cursor')),
          );
          expect(regionAfter.cursor, isNot(SystemMouseCursors.resizeRow));
        },
      );

      testWidgets('does not show the resize cursor for a plain click', (
        tester,
      ) async {
        await _pump(tester, []);

        await _clickAt(tester, const Offset(200, 192));

        final region = tester.widget<MouseRegion>(
          find.byKey(const Key('day-grid-background-cursor')),
        );
        expect(region.cursor, isNot(SystemMouseCursors.resizeRow));
      });

      testWidgets(
        'the actual resolved system cursor stays the resize cursor even '
        'when dragging upward moves the pointer over the rendered draft '
        'box itself '
        "(regression: an upward drag's floor-snapped box top sits above "
        'the real pointer position, so the pointer ends up hovering the '
        'draft box — which has no cursor override — rather than the '
        'background behind it)',
        (tester) async {
          await _pump(tester, []);

          final gesture = await tester.startGesture(
            const Offset(200, 192),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, -32));
          await tester.pump();

          // Mouse pointers default to device id 1 (see `TestPointer`).
          expect(
            RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
            SystemMouseCursors.resizeRow,
          );

          await gesture.up();
        },
      );
    });

    group('landzone', () {
      testWidgets('does not show when no drag is in progress', (tester) async {
        await _pump(tester, [_workBlock]);

        expect(find.byKey(const Key('day-grid-landzone')), findsNothing);
      });

      testWidgets('shows at the drag target time when this grid is the '
          'target', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(dragStateProvider.notifier)
            .start(
              block: _workBlock,
              originalColumn: DayColumn(_date),
              controller: const DayScheduleController(),
              pointerGlobalPosition: Offset.zero,
            );
        container
            .read(dragStateProvider.notifier)
            .updatePointer(
              Offset.zero,
              targetColumn: DayColumn(_date),
              targetStart: DateTime(2026, 9, 9, 11),
            );

        await _pump(tester, [_workBlock], container: container);

        // The key is on the landzone's own Positioned, so it's found
        // directly rather than via find.ancestor (which would look for a
        // strict ancestor of type Positioned, and there isn't one).
        final landzone = tester.widget<Positioned>(
          find.byKey(const Key('day-grid-landzone')),
        );
        // 11:00 is 5 hours (20 slots) after the 6:00 day start.
        expect(landzone.top, 20 * _slotHeight);
        // Work is a 4-hour block, unchanged by the move.
        expect(landzone.height, 16 * _slotHeight);

        // Shows the real block's title (via the separate title-overlay
        // layer — see `_titleOverlay`) and style, framed with a dashed
        // border rather than a plain shaded box.
        expect(find.text('Work'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('day-grid-landzone')),
            matching: find.byType(CustomPaint),
          ),
          findsWidgets,
        );
      });

      testWidgets('does not show when this grid is not the drag target', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(dragStateProvider.notifier)
            .start(
              block: _workBlock,
              originalColumn: DayColumn(_date),
              controller: const DayScheduleController(),
              pointerGlobalPosition: Offset.zero,
            );
        container
            .read(dragStateProvider.notifier)
            .updatePointer(
              Offset.zero,
              targetColumn: DayColumn(DateTime(2026, 9, 10)),
              targetStart: DateTime(2026, 9, 10, 11),
            );

        await _pump(tester, [_workBlock], container: container);

        expect(find.byKey(const Key('day-grid-landzone')), findsNothing);
      });

      testWidgets('hides the real block in its origin column while '
          'dragging, replacing it with the landzone preview', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(dragStateProvider.notifier)
            .start(
              block: _workBlock,
              originalColumn: DayColumn(_date),
              controller: const DayScheduleController(),
              pointerGlobalPosition: Offset.zero,
            );

        await _pump(tester, [_workBlock], container: container);

        // "Work" still appears exactly once, via the landzone preview
        // (which starts at the block's own original slot) — not via the
        // real block, which is hidden for the duration of the drag.
        expect(find.text('Work'), findsOneWidget);
        expect(find.byKey(const Key('day-grid-landzone')), findsOneWidget);
      });
    });

    group('block drag', () {
      testWidgets('a mouse drag on a block starts immediately, no hold '
          'needed', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        // 300 is inside Work's y range (192-448).
        final gesture = await tester.startGesture(
          const Offset(200, 300),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();

        expect(container.read(dragStateProvider), isNotNull);
        await gesture.up();
      });

      testWidgets('a touch drag on a block requires a long-press to start', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        final gesture = await tester.startGesture(const Offset(200, 300));
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();

        // No long-press timeout elapsed yet: no drag started.
        expect(container.read(dragStateProvider), isNull);

        await gesture.up();
      });

      testWidgets('a long-press-and-move on a block starts a drag on '
          'touch', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        final gesture = await _startTouchDrag(tester, const Offset(200, 300));
        await gesture.moveBy(const Offset(0, 32));
        await tester.pump();

        expect(container.read(dragStateProvider), isNotNull);
        await gesture.up();
      });

      testWidgets('releasing a drag over a valid slot commits the move', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        const startPosition = Offset(200, 300);
        const dropPosition = Offset(200, 332); // +32px = 2 slots down.

        final gesture = await _startTouchDrag(tester, startPosition);
        await gesture.moveBy(dropPosition - startPosition);
        await tester.pump();
        await gesture.up();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(container.read(dragStateProvider), isNull);

        // The exact target the drop should have landed on, computed the
        // same way `resolveDragTarget` does, from the grid's real render
        // box rather than an assumed pixel-to-time mapping.
        final gridTopLeft = tester.getTopLeft(find.byType(DayGrid));
        final expectedStart = slotStartForOffset(
          day: _date,
          dy: dropPosition.dy - gridTopLeft.dy,
          settings: _settings,
          slotHeight: _slotHeight,
        );
        expect(expectedStart, isNotNull);

        // A successful `drop()` actually moves the block's start time; a
        // silent `cancel()` (e.g. because `resolveDragTarget` couldn't find
        // the keyed `DayGrid`) would leave it unchanged. Reading the block
        // back through the provider distinguishes the two.
        final blocks = await container.read(dayBlocksProvider(_date).future);
        final moved = blocks.singleWhere((b) => b.id == _workBlock.id);
        final duration = _workBlock.end.difference(_workBlock.start);
        expect(moved.start, expectedStart);
        expect(moved.end, expectedStart!.add(duration));
      });

      testWidgets('a locked block ignores drag gestures', (tester) async {
        final locked = TimeObject(
          id: '1',
          title: 'Locked',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 13),
          kind: BlockKind.frame,
          locked: true,
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [locked], container: container);

        final gesture = await tester.startGesture(
          const Offset(200, 300),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();

        expect(container.read(dragStateProvider), isNull);
        await gesture.up();
      });

      testWidgets('a plain tap on a block still dismisses an open draft', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, [_workBlock]);
        await _clickAt(tester, const Offset(200, 500));
        expect(find.bySemanticsLabel('Create Event'), findsOneWidget);

        await tester.tapAt(const Offset(200, 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.bySemanticsLabel('Create Event'), findsNothing);
        semantics.dispose();
      });

      testWidgets('a plain tap on a non-locked block opens the edit modal', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        // `BlockEditModal` looks up the live block from `dayBlocksProvider`
        // by id every rebuild, so the tapped block must actually be seeded
        // into that provider (with its real, repository-assigned id) rather
        // than only passed via `DayGrid`'s own `blocks` parameter — otherwise
        // the modal finds no matching block and immediately closes itself.
        await container.read(dayBlocksProvider(_date).future);
        final seeded = await container
            .read(dayBlocksProvider(_date).notifier)
            .addBlock(
              start: _workBlock.start,
              end: _workBlock.end,
              kind: _workBlock.kind,
              title: _workBlock.title,
            );
        await _pump(tester, [seeded], container: container);

        await tester.tapAt(const Offset(200, 300));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Work'), findsWidgets);
        expect(find.byIcon(Icons.close), findsOneWidget);
      });
    });

    group('block resize', () {
      testWidgets('dragging the bottom edge handle starts a resize on the '
          'end edge', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        // Work spans y 192-448; the bottom resize handle straddles y=448.
        final gesture = await tester.startGesture(const Offset(200, 445));
        await gesture.moveBy(const Offset(0, 32));
        await tester.pump();

        final state = container.read(resizeStateProvider);
        expect(state, isNotNull);
        expect(state!.edge, ResizeEdge.end);
        await gesture.up();
      });

      testWidgets('dragging the top edge handle starts a resize on the '
          'start edge', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        // Work spans y 192-448; the top resize handle straddles y=192.
        final gesture = await tester.startGesture(const Offset(200, 195));
        await gesture.moveBy(const Offset(0, -32));
        await tester.pump();

        final state = container.read(resizeStateProvider);
        expect(state, isNotNull);
        expect(state!.edge, ResizeEdge.start);
        await gesture.up();
      });

      testWidgets('shows the resize draft shadow while resizing', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        final gesture = await tester.startGesture(const Offset(200, 445));
        await gesture.moveBy(const Offset(0, 32));
        await tester.pump();

        expect(find.byKey(const Key('day-grid-resize-draft')), findsOneWidget);
        await gesture.up();
      });

      testWidgets('releasing a bottom-edge resize commits the new end '
          'time', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        const startPosition = Offset(200, 445);
        const dropPosition = Offset(200, 477);
        final gesture = await tester.startGesture(startPosition);
        await gesture.moveBy(dropPosition - startPosition);
        await tester.pump();
        await gesture.up();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(container.read(resizeStateProvider), isNull);

        // Computed the same way `slotStartForOffset` resolves it in
        // production, from the grid's real render box, rather than an
        // assumed pixel-to-time mapping.
        final gridTopLeft = tester.getTopLeft(find.byType(DayGrid));
        final expectedEnd = slotStartForOffset(
          day: _date,
          dy: dropPosition.dy - gridTopLeft.dy,
          settings: _settings,
          slotHeight: _slotHeight,
        );
        expect(expectedEnd, isNotNull);

        final blocks = await container.read(dayBlocksProvider(_date).future);
        final resized = blocks.singleWhere((b) => b.id == _workBlock.id);
        expect(resized.start, _workBlock.start);
        expect(resized.end, expectedEnd);
      });

      testWidgets('a locked block ignores resize gestures', (tester) async {
        final locked = TimeObject(
          id: '1',
          title: 'Locked',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 13),
          kind: BlockKind.frame,
          locked: true,
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [locked], container: container);

        final gesture = await tester.startGesture(const Offset(200, 445));
        await gesture.moveBy(const Offset(0, 32));
        await tester.pump();

        expect(container.read(resizeStateProvider), isNull);
        await gesture.up();
      });
    });

    group('block resize — device racing', () {
      testWidgets(
        'a quick touch drag near a block edge starts a resize without a '
        'long-press',
        (tester) async {
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await _pump(tester, [_workBlock], container: container);

          // Work's bottom edge is at y=448.
          final gesture = await tester.startGesture(const Offset(200, 445));
          await gesture.moveBy(const Offset(0, 20));
          await tester.pump();

          expect(container.read(resizeStateProvider), isNotNull);
          expect(container.read(dragStateProvider), isNull);
          await gesture.up();
        },
      );

      testWidgets(
        'holding (long-press) near a block edge on touch starts a move, '
        'not a resize',
        (tester) async {
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await _pump(tester, [_workBlock], container: container);

          final gesture = await _startTouchDrag(tester, const Offset(200, 445));
          await gesture.moveBy(const Offset(0, 20));
          await tester.pump();

          expect(container.read(dragStateProvider), isNotNull);
          expect(container.read(resizeStateProvider), isNull);
          await gesture.up();
        },
      );

      testWidgets(
        'mouse dragging from the block body (away from the edge) starts a '
        'move',
        (tester) async {
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await _pump(tester, [_workBlock], container: container);

          final gesture = await tester.startGesture(
            const Offset(200, 300),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 20));
          await tester.pump();

          expect(container.read(dragStateProvider), isNotNull);
          expect(container.read(resizeStateProvider), isNull);
          await gesture.up();
        },
      );

      testWidgets('mouse dragging from the thin edge strip starts a resize', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        // Work's bottom edge is at y=448; the classic mouse strip sits
        // right on it, unlike touch's much larger bleed.
        final gesture = await tester.startGesture(
          const Offset(200, 449),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();

        expect(container.read(resizeStateProvider), isNotNull);
        expect(container.read(dragStateProvider), isNull);
        await gesture.up();
      });

      testWidgets('mouse can still move an extra-small block from its body', (
        tester,
      ) async {
        final tiny = TimeObject(
          id: '1',
          title: 'Tiny',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 9, 15),
          kind: BlockKind.anchor,
          locked: false,
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: DayGrid(
                  key: scheduleGridKeyFor(DayColumn(_date)),
                  date: _date,
                  column: DayColumn(_date),
                  controller: const DayScheduleController(),
                  actions: dayScheduleBlockActions,
                  blocks: [tiny],
                  settings: _settings,
                  slotHeight: 8,
                  onCreateBlock: ({
                    required start,
                    required end,
                    required kind,
                  }) {},
                ),
              ),
            ),
          ),
        );

        // 9:00 is 3 hours after the 6:00 day start = 12 slots * 8px = 96.
        // The block is one 15-minute slot tall (8px): it spans y 96-104,
        // so its exact vertical center is y=100.
        final gesture = await tester.startGesture(
          const Offset(200, 100),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();

        expect(container.read(dragStateProvider), isNotNull);
        expect(container.read(resizeStateProvider), isNull);
        await gesture.up();
      });

      testWidgets(
        'a short block sandwiched between two back-to-back neighbors is '
        'still movable from its own body',
        (tester) async {
          // Three touching 15-minute blocks: a busy, back-to-back part of
          // the day like a packed evening. Without per-block bleed
          // clamping, a neighbor's bled hit region could swallow 'b'
          // entirely, since its true body (one slot) is shorter than the
          // combined bleed of the strips around it.
          final a = TimeObject(
            id: 'a',
            title: 'A',
            start: DateTime(2026, 9, 9, 9),
            end: DateTime(2026, 9, 9, 9, 15),
            kind: BlockKind.anchor,
            locked: false,
          );
          final b = TimeObject(
            id: 'b',
            title: 'B',
            start: DateTime(2026, 9, 9, 9, 15),
            end: DateTime(2026, 9, 9, 9, 30),
            kind: BlockKind.anchor,
            locked: false,
          );
          final c = TimeObject(
            id: 'c',
            title: 'C',
            start: DateTime(2026, 9, 9, 9, 30),
            end: DateTime(2026, 9, 9, 9, 45),
            kind: BlockKind.anchor,
            locked: false,
          );
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await _pump(tester, [a, b, c], container: container);

          // 9:15 is 3h15m after the 6:00 day start = 13 slots * 16px =
          // 208. 'b' spans y 208-224 (one 15-minute slot); its exact
          // vertical center is y=216.
          final gesture = await tester.startGesture(
            const Offset(200, 216),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 20));
          await tester.pump();

          final state = container.read(dragStateProvider);
          expect(state, isNotNull);
          expect(state!.block.id, 'b');
          await gesture.up();
        },
      );

      testWidgets('a mouse hovering near a block edge shows a resize '
          'cursor', (tester) async {
        await _pump(tester, [_workBlock]);

        final region = tester.widget<MouseRegion>(
          find.descendant(
            of: find.byKey(const Key('day-grid-resize-end-handle')),
            matching: find.byType(MouseRegion),
          ),
        );

        expect(region.cursor, SystemMouseCursors.resizeRow);
      });

      testWidgets(
        "resizing a block's end all the way down reaches the exact day "
        'end, not one slot short',
        (tester) async {
          // 22:30 is 16h30m after the 6:00 day start = 66 slots * 16px =
          // 1056; the block (22:30-22:45) spans y 1056-1072.
          final lastBlock = TimeObject(
            id: '1',
            title: 'Late',
            start: DateTime(2026, 9, 9, 22, 30),
            end: DateTime(2026, 9, 9, 22, 45),
            kind: BlockKind.anchor,
            locked: false,
          );
          // The default test surface (800x600) is shorter than the day
          // grid's full height (1088px here); widen it so the block near
          // day end, and the gesture dragged past it, are actually on
          // screen and hit-testable.
          tester.view.physicalSize = const Size(800, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await _pump(tester, [lastBlock], container: container);

          // Start within the true bottom edge strip (not relying on any
          // bleed past it) and drag well past the grid's own bottom.
          final gesture = await tester.startGesture(
            const Offset(200, 1069),
            kind: PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 200));
          await tester.pump();
          await gesture.up();
          await tester.pump();
          await tester.pumpAndSettle();

          final blocks = await container.read(dayBlocksProvider(_date).future);
          final resized = blocks.singleWhere((b) => b.id == lastBlock.id);
          expect(resized.end, DateTime(2026, 9, 9, _settings.dayEndHour));
        },
      );
    });
  });
}
