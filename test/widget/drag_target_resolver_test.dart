import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);
const _slotHeight = 16.0;
final _dates = [DateTime(2026, 9, 9), DateTime(2026, 9, 10)];

Future<void> _pumpTwoColumns(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          for (final date in _dates)
            SizedBox(
              key: dayGridKeyFor(date),
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
        candidateDates: _dates,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(target?.date, _dates[1]);
      expect(target?.start, DateTime(2026, 9, 10, 9));
    });

    testWidgets('returns null when the position is over no known column', (
      tester,
    ) async {
      await _pumpTwoColumns(tester);

      final target = resolveDragTarget(
        globalPosition: const Offset(3000, 192),
        candidateDates: _dates,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(target, isNull);
    });

    testWidgets('returns null when the position is below the grid', (
      tester,
    ) async {
      await _pumpTwoColumns(tester);

      final target = resolveDragTarget(
        globalPosition: const Offset(10, 5000),
        candidateDates: _dates,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(target, isNull);
    });
  });
}
