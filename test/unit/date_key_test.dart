import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/date_key.dart';

void main() {
  group('dateKeyFor', () {
    test('formats as zero-padded yyyy-MM-dd', () {
      expect(dateKeyFor(DateTime(2030, 1, 5)), '2030-01-05');
    });

    test('two DateTimes on the same day produce the same key regardless '
        'of time of day', () {
      expect(
        dateKeyFor(DateTime(2030, 1, 5, 23, 59)),
        dateKeyFor(DateTime(2030, 1, 5, 0, 1)),
      );
    });

    test('different days produce different keys', () {
      expect(
        dateKeyFor(DateTime(2030, 1, 5)),
        isNot(dateKeyFor(DateTime(2030, 1, 6))),
      );
    });
  });
}
