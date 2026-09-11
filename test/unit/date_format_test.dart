import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/date_format.dart';

void main() {
  group('formatDate', () {
    test('formats using a European dd/MM/yyyy pattern', () {
      final date = DateTime(2026, 9, 9);

      expect(formatDate(date, 'dd/MM/yyyy'), '09/09/2026');
    });

    test('formats using a US MM/dd/yyyy pattern', () {
      final date = DateTime(2026, 12, 3);

      expect(formatDate(date, 'MM/dd/yyyy'), '12/03/2026');
    });
  });

  group('formatHm', () {
    test('zero-pads both hour and minute', () {
      expect(formatHm(DateTime(2026, 9, 9, 7, 5)), '07:05');
    });

    test('formats a time with no padding needed', () {
      expect(formatHm(DateTime(2026, 9, 9, 13, 30)), '13:30');
    });
  });

  group('formatDayHeaderLabel', () {
    test('includes the weekday name when showWeekday is true', () {
      final date = DateTime(2026, 9, 9); // a Wednesday

      expect(
        formatDayHeaderLabel(date, showWeekday: true, pattern: 'dd/MM/yyyy'),
        'Wednesday, 09/09/2026',
      );
    });

    test('omits the weekday name when showWeekday is false', () {
      final date = DateTime(2026, 9, 9);

      expect(
        formatDayHeaderLabel(date, showWeekday: false, pattern: 'dd/MM/yyyy'),
        '09/09/2026',
      );
    });
  });
}
