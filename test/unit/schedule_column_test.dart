import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';

void main() {
  group('DayColumn', () {
    test('equal when the calendar day matches, ignoring time of day', () {
      expect(
        DayColumn(DateTime(2026, 9, 9, 10, 30)),
        DayColumn(DateTime(2026, 9, 9, 22)),
      );
    });

    test('not equal on a different calendar day', () {
      expect(
        DayColumn(DateTime(2026, 9, 9)) == DayColumn(DateTime(2026, 9, 10)),
        isFalse,
      );
    });

    test('hashCode matches for the same calendar day', () {
      expect(
        DayColumn(DateTime(2026, 9, 9, 10, 30)).hashCode,
        DayColumn(DateTime(2026, 9, 9, 22)).hashCode,
      );
    });
  });

  group('TemplateColumn', () {
    test('equal when the templateId matches', () {
      expect(const TemplateColumn('t1'), const TemplateColumn('t1'));
    });

    test('not equal for a different templateId', () {
      expect(const TemplateColumn('t1') == const TemplateColumn('t2'), isFalse);
    });
  });

  test('a DayColumn is never equal to a TemplateColumn', () {
    expect(
      DayColumn(DateTime(2026, 9, 9)) == const TemplateColumn('2026-09-09'),
      isFalse,
    );
  });

  group('anchorDateFor', () {
    test('returns the DayColumn\'s own date', () {
      final date = DateTime(2026, 9, 9);
      expect(anchorDateFor(DayColumn(date)), date);
    });

    test('returns templateAnchorDate for a TemplateColumn', () {
      expect(anchorDateFor(const TemplateColumn('t1')), templateAnchorDate);
    });
  });
}
