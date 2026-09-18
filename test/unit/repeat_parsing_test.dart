import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/task/repeat_parsing.dart';

void main() {
  group('extractTrailingRepeat', () {
    test('extracts a compact "every 1w" typed at the start of the title', () {
      final result = extractTrailingRepeat('every 1w ');

      expect(result, isNotNull);
      expect(result!.repeat, '1w');
      expect(result.title, '');
    });

    test('extracts a compact repeat typed after other words, leaving them '
        'intact', () {
      final result = extractTrailingRepeat('Water plants every 1w ');

      expect(result, isNotNull);
      expect(result!.repeat, '1w');
      expect(result.title, 'Water plants ');
    });

    test('is case-insensitive on "every"', () {
      final result = extractTrailingRepeat('Water plants Every 1w ');

      expect(result, isNotNull);
      expect(result!.title, 'Water plants ');
    });

    for (final entry in {
      'day': 'd',
      'days': 'd',
      'week': 'w',
      'weeks': 'w',
      'month': 'm',
      'months': 'm',
      'year': 'y',
      'years': 'y',
    }.entries) {
      test(
        'normalizes spelled-out "every 2 ${entry.key}" to "2${entry.value}"',
        () {
          final result = extractTrailingRepeat('every 2 ${entry.key} ');

          expect(result!.repeat, '2${entry.value}');
        },
      );
    }

    test('returns null when the text does not end with a space', () {
      expect(extractTrailingRepeat('every 1w'), isNull);
    });

    test('returns null when there is no "every ..." before the trailing '
        'space', () {
      expect(extractTrailingRepeat('Water plants '), isNull);
    });

    test('returns null for an unrecognized unit', () {
      expect(extractTrailingRepeat('every 1x '), isNull);
    });

    test('returns null for empty text', () {
      expect(extractTrailingRepeat(''), isNull);
    });
  });

  group('extractFinalRepeat', () {
    test('extracts a repeat at the very end, with no trailing space', () {
      final result = extractFinalRepeat('Water plants every 1w');

      expect(result, isNotNull);
      expect(result!.repeat, '1w');
      expect(result.title, 'Water plants ');
    });

    test('returns null when the repeat has a trailing space (not the last '
        'characters)', () {
      expect(extractFinalRepeat('Water plants every 1w '), isNull);
    });

    test('returns null when there is no "every ..." at the end', () {
      expect(extractFinalRepeat('Water plants'), isNull);
    });

    test('returns null for empty text', () {
      expect(extractFinalRepeat(''), isNull);
    });
  });

  group('nextOccurrence', () {
    test('adds days for a "d" repeat', () {
      final from = DateTime(2026, 3, 5);
      expect(nextOccurrence(from, '3d'), DateTime(2026, 3, 8));
    });

    test('adds weeks (as days) for a "w" repeat', () {
      final from = DateTime(2026, 3, 5);
      expect(nextOccurrence(from, '2w'), DateTime(2026, 3, 19));
    });

    test('adds calendar months for a "m" repeat', () {
      final from = DateTime(2026, 1, 15);
      expect(nextOccurrence(from, '1m'), DateTime(2026, 2, 15));
    });

    test('adds calendar years for a "y" repeat', () {
      final from = DateTime(2026, 3, 5);
      expect(nextOccurrence(from, '1y'), DateTime(2027, 3, 5));
    });
  });
}
