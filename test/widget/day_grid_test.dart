import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';

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
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: DayGrid(
        date: _date,
        blocks: blocks,
        settings: _settings,
        slotHeight: _slotHeight,
        onSwipeStart: onSwipeStart,
        onSwipeUpdate: onSwipeUpdate,
        onSwipeEnd: onSwipeEnd,
        onCreateBlock:
            onCreateBlock ?? ({required start, required end, required kind}) {},
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
        MaterialApp(
          home: Scaffold(
            body: DayGrid(
              date: _date,
              blocks: const [],
              settings: _settings,
              slotHeight: 8,
              onCreateBlock: ({required start, required end, required kind}) {},
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);

      expect(sizedBox.height, 68 * 8.0);
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
  });
}
