import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/week_utils.dart';

void main() {
  group('startOfWeek', () {
    test('returns the Monday of a Monday-first week containing a Wednesday', () {
      final wednesday = DateTime(2026, 9, 9);

      final start = startOfWeek(wednesday, firstDayOfWeek: DateTime.monday);

      expect(start, DateTime(2026, 9, 7));
    });

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
}
