import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/widgets/hour_gutter.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);

void main() {
  testWidgets(
    'HourGutter sizes itself to span day-start through day-end',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HourGutter(settings: _settings, slotHeight: 16),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);

      // 6:00 to 23:00 is 17 hours = 68 slots.
      expect(sizedBox.height, 68 * 16.0);
      expect(sizedBox.width, HourGutter.width);
    },
  );
}
