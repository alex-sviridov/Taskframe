import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/task/tag_parsing.dart';

void main() {
  group('extractTrailingTag', () {
    test('extracts a tag typed at the start of the title', () {
      final result = extractTrailingTag('#groceries ');

      expect(result, isNotNull);
      expect(result!.tag, 'groceries');
      expect(result.title, '');
    });

    test('extracts a tag typed after other words, leaving them intact', () {
      final result = extractTrailingTag('Buy #groceries ');

      expect(result, isNotNull);
      expect(result!.tag, 'groceries');
      expect(result.title, 'Buy ');
    });

    test('lowercases the extracted tag', () {
      final result = extractTrailingTag('Buy #Groceries ');

      expect(result!.tag, 'groceries');
    });

    test('returns null when the text does not end with a space', () {
      expect(extractTrailingTag('Buy #groceries'), isNull);
    });

    test('returns null when there is no #tag before the trailing space', () {
      expect(extractTrailingTag('Buy milk '), isNull);
    });

    test('returns null for a bare # with no word characters', () {
      expect(extractTrailingTag('Buy # '), isNull);
    });

    test('returns null for empty text', () {
      expect(extractTrailingTag(''), isNull);
    });

    test('extracts a tag with non-ASCII letters', () {
      final result = extractTrailingTag('Купить #продукты ');

      expect(result, isNotNull);
      expect(result!.tag, 'продукты');
      expect(result.title, 'Купить ');
    });
  });

  group('extractFinalTag', () {
    test('extracts a tag at the very end, with no trailing space', () {
      final result = extractFinalTag('Buy #groceries');

      expect(result, isNotNull);
      expect(result!.tag, 'groceries');
      expect(result.title, 'Buy ');
    });

    test('extracts a tag that is the entire text', () {
      final result = extractFinalTag('#groceries');

      expect(result, isNotNull);
      expect(result!.tag, 'groceries');
      expect(result.title, '');
    });

    test('lowercases the extracted tag', () {
      final result = extractFinalTag('Buy #Groceries');

      expect(result!.tag, 'groceries');
    });

    test('returns null when the tag has a trailing space (not the last '
        'character)', () {
      expect(extractFinalTag('Buy #groceries '), isNull);
    });

    test('returns null when there is no #tag at the end', () {
      expect(extractFinalTag('Buy milk'), isNull);
    });

    test('returns null for a bare # with no word characters', () {
      expect(extractFinalTag('Buy #'), isNull);
    });

    test('returns null for empty text', () {
      expect(extractFinalTag(''), isNull);
    });

    test('extracts a tag with non-ASCII letters', () {
      final result = extractFinalTag('Купить #продукты');

      expect(result, isNotNull);
      expect(result!.tag, 'продукты');
      expect(result.title, 'Купить ');
    });
  });
}
