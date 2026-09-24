import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/category_parsing.dart';

void main() {
  final work = Category(id: 'cat-1', name: 'Work', colorValue: 0xFF2196F3);
  final home = Category(id: 'cat-2', name: 'Home', colorValue: 0xFF4CAF50);
  final housekeeping = Category(
    id: 'cat-3',
    name: 'уборка',
    colorValue: 0xFFFFC107,
  );
  final sideProject = Category(
    id: 'cat-4',
    name: 'side-project',
    colorValue: 0xFF9C27B0,
  );
  final categories = [work, home, housekeeping, sideProject];

  group('extractTrailingCategory', () {
    test('extracts a category typed at the start of the title', () {
      final result = extractTrailingCategory('@work ', categories);

      expect(result, isNotNull);
      expect(result!.categoryId, work.id);
      expect(result.title, '');
    });

    test('extracts a category typed after other words, leaving them '
        'intact', () {
      final result = extractTrailingCategory('Buy milk @work ', categories);

      expect(result, isNotNull);
      expect(result!.categoryId, work.id);
      expect(result.title, 'Buy milk ');
    });

    test('matches case-insensitively', () {
      final result = extractTrailingCategory('Buy milk @WORK ', categories);

      expect(result!.categoryId, work.id);
    });

    test('returns null when the text does not end with a space', () {
      expect(extractTrailingCategory('Buy milk @work', categories), isNull);
    });

    test('returns null when there is no @category before the trailing '
        'space', () {
      expect(extractTrailingCategory('Buy milk ', categories), isNull);
    });

    test('returns null when the word matches no existing category '
        '(left as plain text)', () {
      expect(extractTrailingCategory('Buy milk @nope ', categories), isNull);
    });

    test('returns null for a bare @ with no word characters', () {
      expect(extractTrailingCategory('Buy @ ', categories), isNull);
    });

    test('returns null for empty text', () {
      expect(extractTrailingCategory('', categories), isNull);
    });

    test('extracts a category whose name has non-ASCII letters', () {
      final result = extractTrailingCategory('Помыть пол @уборка ', categories);

      expect(result, isNotNull);
      expect(result!.categoryId, housekeeping.id);
      expect(result.title, 'Помыть пол ');
    });

    test('extracts a category whose name has a hyphen', () {
      final result = extractTrailingCategory(
        'Fix bug @side-project ',
        categories,
      );

      expect(result, isNotNull);
      expect(result!.categoryId, sideProject.id);
      expect(result.title, 'Fix bug ');
    });

    test('a symbol other than "-" right before the trailing space breaks '
        'the category word, so nothing is extracted', () {
      expect(extractTrailingCategory('Buy milk @work! ', categories), isNull);
    });
  });

  group('extractFinalCategory', () {
    test('extracts a category at the very end, with no trailing space', () {
      final result = extractFinalCategory('Buy milk @work', categories);

      expect(result, isNotNull);
      expect(result!.categoryId, work.id);
      expect(result.title, 'Buy milk ');
    });

    test('extracts a category that is the entire text', () {
      final result = extractFinalCategory('@home', categories);

      expect(result, isNotNull);
      expect(result!.categoryId, home.id);
      expect(result.title, '');
    });

    test('matches case-insensitively', () {
      final result = extractFinalCategory('Buy milk @HOME', categories);

      expect(result!.categoryId, home.id);
    });

    test('returns null when the category has a trailing space (not the '
        'last character)', () {
      expect(extractFinalCategory('Buy milk @work ', categories), isNull);
    });

    test('returns null when there is no @category at the end', () {
      expect(extractFinalCategory('Buy milk', categories), isNull);
    });

    test('returns null when the word matches no existing category', () {
      expect(extractFinalCategory('Buy milk @nope', categories), isNull);
    });

    test('returns null for a bare @ with no word characters', () {
      expect(extractFinalCategory('Buy @', categories), isNull);
    });

    test('returns null for empty text', () {
      expect(extractFinalCategory('', categories), isNull);
    });

    test('extracts a category whose name has non-ASCII letters', () {
      final result = extractFinalCategory('Помыть пол @уборка', categories);

      expect(result, isNotNull);
      expect(result!.categoryId, housekeeping.id);
      expect(result.title, 'Помыть пол ');
    });

    test('extracts a category whose name has a hyphen', () {
      final result = extractFinalCategory('Fix bug @side-project', categories);

      expect(result, isNotNull);
      expect(result!.categoryId, sideProject.id);
      expect(result.title, 'Fix bug ');
    });

    test('a trailing symbol other than "-" breaks the category word, so '
        'nothing is extracted', () {
      expect(extractFinalCategory('Buy milk @work!', categories), isNull);
    });
  });
}
