import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/week_utils.dart';

void main() {
  group('startOfWeek', () {
    test(
      'returns the Monday of a Monday-first week containing a Wednesday',
      () {
        final wednesday = DateTime(2026, 9, 9);

        final start = startOfWeek(wednesday, firstDayOfWeek: DateTime.monday);

        expect(start, DateTime(2026, 9, 7));
      },
    );

    test('returns the same date when it already is the first day', () {
      final monday = DateTime(2026, 9, 7);

      final start = startOfWeek(monday, firstDayOfWeek: DateTime.monday);

      expect(start, DateTime(2026, 9, 7));
    });

    test('supports a Sunday-first week', () {
      final wednesday = DateTime(2026, 9, 9);

      final start = startOfWeek(wednesday, firstDayOfWeek: DateTime.sunday);

      expect(start, DateTime(2026, 9, 6));
    });
  });

  group('isSameDay', () {
    test('is true for the same calendar date with different times', () {
      expect(
        isSameDay(DateTime(2026, 9, 9, 8), DateTime(2026, 9, 9, 22, 30)),
        isTrue,
      );
    });

    test('is false for different calendar dates', () {
      expect(isSameDay(DateTime(2026, 9, 9), DateTime(2026, 9, 10)), isFalse);
    });

    test('is false for the same day and month in a different year', () {
      expect(isSameDay(DateTime(2026, 9, 9), DateTime(2027, 9, 9)), isFalse);
    });
  });
}
