import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);
const _slotHeight = 16.0;
final _columns = [
  DayColumn(DateTime(2026, 9, 9)),
  DayColumn(DateTime(2026, 9, 10)),
];

/// Grows the test surface so a full day's 1088px-tall column (68 slots *
/// 16) actually fits without being constrained down to the default 600px
/// test viewport — otherwise `SizedBox`'s own height never reaches the
/// grid's later slots and a `globalPosition` down there fails `rect.
/// contains` for reasons unrelated to whatever the test means to check.
void _growViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpTwoColumns(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          for (final column in _columns)
            SizedBox(
              key: scheduleGridKeyFor(column),
              width: 300,
              height: 1088, // 68 slots * 16.
            ),
        ],
      ),
    ),
  ),
);

void main() {
  group('resolveDragTarget', () {
    testWidgets('finds the column and snapped time under the position', (
      tester,
    ) async {
      await _pumpTwoColumns(tester);
      // Second column starts at x=300; y=192 is 3 hours (12 slots) past
      // the 6:00 day start.
      final target = resolveDragTarget(
        globalPosition: const Offset(310, 192),
        origin: _columns[0],
        candidateColumns: _columns,
        settings: _settings,
        slotHeight: _slotHeight,
        blockDuration: const Duration(minutes: 30),
      );

      expect(target?.column, _columns[1]);
      expect(target?.start, DateTime(2026, 9, 10, 9));
    });

    testWidgets('returns null when the position is over no known column', (
      tester,
    ) async {
      await _pumpTwoColumns(tester);

      final target = resolveDragTarget(
        globalPosition: const Offset(3000, 192),
        origin: _columns[0],
        candidateColumns: _columns,
        settings: _settings,
        slotHeight: _slotHeight,
        blockDuration: const Duration(minutes: 30),
      );

      expect(target, isNull);
    });

    testWidgets('returns null when the position is below the grid', (
      tester,
    ) async {
      await _pumpTwoColumns(tester);

      final target = resolveDragTarget(
        globalPosition: const Offset(10, 5000),
        origin: _columns[0],
        candidateColumns: _columns,
        settings: _settings,
        slotHeight: _slotHeight,
        blockDuration: const Duration(minutes: 30),
      );

      expect(target, isNull);
    });

    testWidgets(
      'returns null when the snapped slot is valid but the block would end '
      'after the day boundary (regression: a long block dragged near day '
      'end must not land with an end wrapped into the next calendar day)',
      (tester) async {
        _growViewport(tester);
        await _pumpTwoColumns(tester);
        // y=1072 is the last valid slot's top (22:45): 67 slots * 16 past
        // the 6:00 day start.
        final target = resolveDragTarget(
          globalPosition: const Offset(10, 1072),
          origin: _columns[0],
          candidateColumns: _columns,
          settings: _settings,
          slotHeight: _slotHeight,
          blockDuration: const Duration(hours: 2),
        );

        expect(target, isNull);
      },
    );

    testWidgets(
      'still finds the snapped slot when the block exactly fits before day '
      'end',
      (tester) async {
        _growViewport(tester);
        await _pumpTwoColumns(tester);

        final target = resolveDragTarget(
          globalPosition: const Offset(10, 1072),
          origin: _columns[0],
          candidateColumns: _columns,
          settings: _settings,
          slotHeight: _slotHeight,
          blockDuration: const Duration(minutes: 15),
        );

        expect(target?.column, _columns[0]);
        expect(target?.start, DateTime(2026, 9, 9, 22, 45));
      },
    );
  });

  group('scheduleGridKeyFor cache growth', () {
    testWidgets(
      'drops keys for dates whose DayGrid has since unmounted, instead of '
      'growing forever as new dates are visited',
      (tester) async {
        final manyColumns = List.generate(
          5,
          (i) => DayColumn(DateTime(2026, 9, 9 + i)),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  for (final column in manyColumns)
                    SizedBox(
                      key: scheduleGridKeyFor(column),
                      width: 10,
                      height: 10,
                    ),
                ],
              ),
            ),
          ),
        );
        expect(scheduleGridKeyCacheSizeForTest(), 5);

        // Replaces every SizedBox above with a single new one for a new
        // date, unmounting the previous 5.
        final newColumn = DayColumn(DateTime(2026, 9, 30));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                key: scheduleGridKeyFor(newColumn),
                width: 10,
                height: 10,
              ),
            ),
          ),
        );

        // The new date's own key is mounted and kept; the previous 5,
        // unmounted, get swept once this frame's prune callback has run.
        expect(scheduleGridKeyCacheSizeForTest(), 1);
      },
    );
  });
}
