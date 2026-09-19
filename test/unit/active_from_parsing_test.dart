import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/task/active_from_parsing.dart';

void main() {
  group('formatActiveFrom', () {
    test('formats as dd/mm/yy, zero-padded', () {
      expect(formatActiveFrom(DateTime(2026, 3, 5)), '05/03/26');
    });
  });

  group('extractTrailingActiveFrom', () {
    test('extracts a dd/mm/yy date typed at the start of the title', () {
      final result = extractTrailingActiveFrom('from 05/03/26 ');

      expect(result, isNotNull);
      expect(result!.activeFrom, DateTime(2026, 3, 5));
      expect(result.title, '');
    });

    test('extracts a dd/mm/yy date typed after other words, leaving them '
        'intact', () {
      final result = extractTrailingActiveFrom('Buy milk from 05/03/26 ');

      expect(result, isNotNull);
      expect(result!.activeFrom, DateTime(2026, 3, 5));
      expect(result.title, 'Buy milk ');
    });

    test('extracts a dd/mm date, assuming the current year', () {
      final result = extractTrailingActiveFrom('Buy milk from 05/03 ');

      expect(result, isNotNull);
      expect(result!.activeFrom, DateTime(DateTime.now().year, 3, 5));
      expect(result.title, 'Buy milk ');
    });

    test('is case-insensitive on "from"', () {
      final result = extractTrailingActiveFrom('Buy milk From 05/03/26 ');

      expect(result, isNotNull);
      expect(result!.title, 'Buy milk ');
    });

    test('a two-digit year is interpreted as 20yy', () {
      final result = extractTrailingActiveFrom('from 05/03/07 ');

      expect(result!.activeFrom, DateTime(2007, 3, 5));
    });

    test('a four-digit year is used as-is', () {
      final result = extractTrailingActiveFrom('from 05/03/2031 ');

      expect(result!.activeFrom, DateTime(2031, 3, 5));
    });

    test('returns null when the text does not end with a space', () {
      expect(extractTrailingActiveFrom('Buy milk from 05/03/26'), isNull);
    });

    test('returns null when there is no "from date" before the trailing '
        'space', () {
      expect(extractTrailingActiveFrom('Buy milk '), isNull);
    });

    test('returns null for an invalid date', () {
      expect(extractTrailingActiveFrom('from 32/13/26 '), isNull);
    });

    test('returns null for empty text', () {
      expect(extractTrailingActiveFrom(''), isNull);
    });
  });

  group('extractFinalActiveFrom', () {
    test('extracts a date at the very end, with no trailing space', () {
      final result = extractFinalActiveFrom('Buy milk from 05/03/26');

      expect(result, isNotNull);
      expect(result!.activeFrom, DateTime(2026, 3, 5));
      expect(result.title, 'Buy milk ');
    });

    test('returns null when the date has a trailing space (not the last '
        'characters)', () {
      expect(extractFinalActiveFrom('Buy milk from 05/03/26 '), isNull);
    });

    test('returns null when there is no "from date" at the end', () {
      expect(extractFinalActiveFrom('Buy milk'), isNull);
    });

    test('returns null for empty text', () {
      expect(extractFinalActiveFrom(''), isNull);
    });
  });
}
