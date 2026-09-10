import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';

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
          key: dayGridKeyFor(_date),
          date: _date,
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

/// Double-taps at [position] by sending two taps close enough together for
/// the gesture arena to recognize a double tap.
Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Starts a touch drag on [block] within a single-column [_pump]ed grid,
/// waiting out the long-press timeout before the first move so the
/// gesture arena has resolved in favor of the long-press recognizer.
Future<TestGesture> _startTouchDrag(
  WidgetTester tester,
  Offset position,
) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.touch,
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return gesture;
}

void main() {
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
        find.ancestor(of: find.text('Work'), matching: find.byType(Positioned)),
      );

      // 9:00 is 3 hours (12 slots) after the 6:00 day start.
      expect(positioned.top, 12 * _slotHeight);
      // A 4-hour block spans 16 slots.
      expect(positioned.height, 16 * _slotHeight);
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
                blocks: const [],
                settings: _settings,
                slotHeight: 8,
                onCreateBlock:
                    ({required start, required end, required kind}) {},
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
                blocks: [_workBlock],
                settings: _settings,
                slotHeight: _slotHeight,
                showHourLabels: false,
                onCreateBlock:
                    ({required start, required end, required kind}) {},
              ),
            ),
          ),
        ),
      );

      final positioned = tester.widget<Positioned>(
        find.ancestor(of: find.text('Work'), matching: find.byType(Positioned)),
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

    testWidgets('a fling starting on a block is not forwarded', (
      tester,
    ) async {
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
      testWidgets('double-tapping free space shows both create buttons', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, []);

        // y 192 is 9:00, well within the empty grid.
        await _doubleTapAt(tester, const Offset(200, 192));

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
        await _doubleTapAt(tester, const Offset(200, 192));

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
        await _doubleTapAt(tester, const Offset(200, 192));

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

          await _doubleTapAt(tester, const Offset(200, 192));
          await tester.tap(find.bySemanticsLabel('Create Event'));
          await tester.pump();

          expect(created!.end, DateTime(2026, 9, 9, 9, 15));
          semantics.dispose();
        },
      );

      testWidgets('tapping outside the draft dismisses it without creating', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        var called = false;
        await _pump(
          tester,
          [],
          onCreateBlock: ({required start, required end, required kind}) {
            called = true;
          },
        );
        await _doubleTapAt(tester, const Offset(200, 192));
        expect(find.bySemanticsLabel('Create Event'), findsOneWidget);

        // A plain single tap elsewhere dismisses the draft. The tap
        // recognizer waits out the double-tap timeout before firing.
        await tester.tapAt(const Offset(200, 400));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.bySemanticsLabel('Create Event'), findsNothing);
        expect(called, isFalse);
        semantics.dispose();
      });
    });

    group('landzone', () {
      testWidgets('does not show when no drag is in progress', (
        tester,
      ) async {
        await _pump(tester, [_workBlock]);

        expect(find.byKey(const Key('day-grid-landzone')), findsNothing);
      });

      testWidgets('shows at the drag target time when this grid is the '
          'target', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(dragStateProvider.notifier).start(
          block: _workBlock,
          originalDate: _date,
          pointerGlobalPosition: const Offset(0, 0),
        );
        container.read(dragStateProvider.notifier).updatePointer(
          const Offset(0, 0),
          targetDate: _date,
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

        // Shows the real block's title and style, framed with a dashed
        // border rather than a plain shaded box.
        expect(
          find.descendant(
            of: find.byKey(const Key('day-grid-landzone')),
            matching: find.text('Work'),
          ),
          findsOneWidget,
        );
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
        container.read(dragStateProvider.notifier).start(
          block: _workBlock,
          originalDate: _date,
          pointerGlobalPosition: const Offset(0, 0),
        );
        container.read(dragStateProvider.notifier).updatePointer(
          const Offset(0, 0),
          targetDate: DateTime(2026, 9, 10),
          targetStart: DateTime(2026, 9, 10, 11),
        );

        await _pump(tester, [_workBlock], container: container);

        expect(find.byKey(const Key('day-grid-landzone')), findsNothing);
      });

      testWidgets('hides the real block in its origin column while '
          'dragging, replacing it with the landzone preview', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(dragStateProvider.notifier).start(
          block: _workBlock,
          originalDate: _date,
          pointerGlobalPosition: const Offset(0, 0),
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

        final gesture = await tester.startGesture(
          const Offset(200, 300),
          kind: PointerDeviceKind.touch,
        );
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

        final gesture = await _startTouchDrag(
          tester,
          const Offset(200, 300),
        );
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
        await _doubleTapAt(tester, const Offset(200, 500));
        expect(find.bySemanticsLabel('Create Event'), findsOneWidget);

        await tester.tapAt(const Offset(200, 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.bySemanticsLabel('Create Event'), findsNothing);
        semantics.dispose();
      });
    });
  });
}
