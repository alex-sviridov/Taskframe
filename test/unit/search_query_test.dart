import 'package:flutter/services.dart' show TextRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/task/search_query.dart';

void main() {
  group('parseSearchQuery', () {
    test('plain text with no tokens is all free text', () {
      final parsed = parseSearchQuery('Buy milk');
      expect(parsed.tagTokens, isEmpty);
      expect(parsed.statusToken, isNull);
      expect(parsed.freeText, 'Buy milk');
    });

    test('a single #tag is extracted, leaving empty free text', () {
      final parsed = parseSearchQuery('#groceries');
      expect(parsed.tagTokens, hasLength(1));
      expect(parsed.tagTokens.single.tag, 'groceries');
      expect(parsed.tagTokens.single.excluded, isFalse);
      expect(parsed.tagTokens.single.range, const TextRange(start: 0, end: 10));
      expect(parsed.freeText, isEmpty);
    });

    test('#!tag is an excluded tag token', () {
      final parsed = parseSearchQuery('#!urgent');
      expect(parsed.tagTokens.single.tag, 'urgent');
      expect(parsed.tagTokens.single.excluded, isTrue);
    });

    test('tag names are lowercased', () {
      final parsed = parseSearchQuery('#GROCERIES');
      expect(parsed.tagTokens.single.tag, 'groceries');
    });

    test('multiple #tags are all extracted, in order', () {
      final parsed = parseSearchQuery('#a #b');
      expect(parsed.tagTokens.map((t) => t.tag), ['a', 'b']);
      expect(parsed.freeText, isEmpty);
    });

    test('/opened is a status token, not excluded', () {
      final parsed = parseSearchQuery('/opened');
      expect(parsed.statusToken, isNotNull);
      expect(parsed.statusToken!.excluded, isFalse);
      expect(parsed.freeText, isEmpty);
    });

    test('/!opened is an excluded status token', () {
      final parsed = parseSearchQuery('/!opened');
      expect(parsed.statusToken!.excluded, isTrue);
    });

    test('/OPENED is recognized case-insensitively', () {
      final parsed = parseSearchQuery('/OPENED');
      expect(parsed.statusToken, isNotNull);
    });

    test('only the first /opened is recognized; a second is left as '
        'plain text', () {
      final parsed = parseSearchQuery('/opened /opened');
      expect(parsed.statusToken!.excluded, isFalse);
      expect(parsed.freeText, '/opened');
    });

    test('/other (not "opened"/"active") is left entirely as plain text', () {
      final parsed = parseSearchQuery('/other');
      expect(parsed.statusToken, isNull);
      expect(parsed.activeToken, isNull);
      expect(parsed.tagTokens, isEmpty);
      expect(parsed.freeText, '/other');
    });

    test('/active is an active token, not excluded', () {
      final parsed = parseSearchQuery('/active');
      expect(parsed.activeToken, isNotNull);
      expect(parsed.activeToken!.excluded, isFalse);
      expect(parsed.freeText, isEmpty);
    });

    test('/!active is an excluded active token', () {
      final parsed = parseSearchQuery('/!active');
      expect(parsed.activeToken!.excluded, isTrue);
    });

    test('only the first /active is recognized; a second is left as '
        'plain text', () {
      final parsed = parseSearchQuery('/active /active');
      expect(parsed.activeToken!.excluded, isFalse);
      expect(parsed.freeText, '/active');
    });

    test('/opened and /active coexist as independent tokens', () {
      final parsed = parseSearchQuery('/opened /active');
      expect(parsed.statusToken!.excluded, isFalse);
      expect(parsed.activeToken!.excluded, isFalse);
      expect(parsed.freeText, isEmpty);
    });

    test('a mixed query extracts tags and status, collapsing the '
        'remaining whitespace into single spaces', () {
      final parsed = parseSearchQuery('Buy milk #groceries /opened extra');
      expect(parsed.tagTokens.map((t) => t.tag), ['groceries']);
      expect(parsed.statusToken!.excluded, isFalse);
      expect(parsed.freeText, 'Buy milk extra');
    });

    test('a single @category is extracted, leaving empty free text', () {
      final parsed = parseSearchQuery('@work');
      expect(parsed.categoryTokens, hasLength(1));
      expect(parsed.categoryTokens.single.category, 'work');
      expect(parsed.categoryTokens.single.excluded, isFalse);
      expect(
        parsed.categoryTokens.single.range,
        const TextRange(start: 0, end: 5),
      );
      expect(parsed.freeText, isEmpty);
    });

    test('@!category is an excluded category token', () {
      final parsed = parseSearchQuery('@!work');
      expect(parsed.categoryTokens.single.category, 'work');
      expect(parsed.categoryTokens.single.excluded, isTrue);
    });

    test('category names are lowercased', () {
      final parsed = parseSearchQuery('@WORK');
      expect(parsed.categoryTokens.single.category, 'work');
    });

    test('multiple @categories are all extracted, in order', () {
      final parsed = parseSearchQuery('@work @home');
      expect(parsed.categoryTokens.map((t) => t.category), ['work', 'home']);
      expect(parsed.freeText, isEmpty);
    });

    test('a category name with non-ASCII letters is extracted', () {
      final parsed = parseSearchQuery('@уборка');
      expect(parsed.categoryTokens.single.category, 'уборка');
    });

    test(
      'adjacent tokens with no space between them still parse as two',
      () {
        final parsed = parseSearchQuery('#a@home');
        expect(parsed.tagTokens.single.tag, 'a');
        expect(parsed.categoryTokens.single.category, 'home');
      },
    );

    test('a mixed query extracts tags, status, and categories together', () {
      final parsed = parseSearchQuery(
        'Buy milk #groceries @home /opened extra',
      );
      expect(parsed.tagTokens.map((t) => t.tag), ['groceries']);
      expect(parsed.categoryTokens.map((t) => t.category), ['home']);
      expect(parsed.statusToken!.excluded, isFalse);
      expect(parsed.freeText, 'Buy milk extra');
    });
  });

  group('orderedTokenRanges', () {
    test('combines tag and status tokens sorted by position, regardless '
        'of which list they came from', () {
      final parsed = parseSearchQuery('/opened #groceries');
      final ranges = orderedTokenRanges(parsed);
      expect(ranges, hasLength(2));
      expect(ranges.first.range.start, 0); // "/opened"
      expect(ranges.last.range.start, 8); // "#groceries"
    });

    test('also includes an active token, sorted by position', () {
      final parsed = parseSearchQuery('/active #groceries');
      final ranges = orderedTokenRanges(parsed);
      expect(ranges, hasLength(2));
      expect(ranges.first.range.start, 0); // "/active"
      expect(ranges.last.range.start, 8); // "#groceries"
    });

    test('also includes category tokens, sorted by position', () {
      final parsed = parseSearchQuery('@work /opened #groceries');
      final ranges = orderedTokenRanges(parsed);
      expect(ranges, hasLength(3));
      expect(ranges[0].range.start, 0); // "@work"
      expect(ranges[1].range.start, 6); // "/opened"
      expect(ranges[2].range.start, 14); // "#groceries"
    });
  });

  group('toggleQueryToken', () {
    test('toggling an included tag to excluded inserts "!" right after '
        'the "#"', () {
      final parsed = parseSearchQuery('#groceries');
      final result = toggleQueryToken(
        '#groceries',
        parsed.tagTokens.single.range,
        currentlyExcluded: false,
        cursorOffset: 0,
      );
      expect(result.text, '#!groceries');
    });

    test('toggling an excluded tag to included removes the "!"', () {
      final result = toggleQueryToken(
        '#!groceries',
        const TextRange(start: 0, end: 11),
        currentlyExcluded: true,
        cursorOffset: 0,
      );
      expect(result.text, '#groceries');
    });

    test('the cursor shifts forward by 1 when it was at or after the '
        'edit point', () {
      // "Buy #groceries", cursor right after "groceries" (offset 14).
      final result = toggleQueryToken(
        'Buy #groceries',
        const TextRange(start: 4, end: 14),
        currentlyExcluded: false,
        cursorOffset: 14,
      );
      expect(result.text, 'Buy #!groceries');
      expect(result.cursorOffset, 15);
    });

    test('the cursor is unchanged when it was before the edit point', () {
      // "Buy #groceries", cursor after "Buy " (offset 4), right at the
      // token's own start — the edit happens one character later (right
      // after the "#"), so this cursor position is unaffected.
      final result = toggleQueryToken(
        'Buy #groceries',
        const TextRange(start: 4, end: 14),
        currentlyExcluded: false,
        cursorOffset: 4,
      );
      expect(result.cursorOffset, 4);
    });

    test('toggling a status token works the same way, with "/"', () {
      final parsed = parseSearchQuery('/opened');
      final result = toggleQueryToken(
        '/opened',
        parsed.statusToken!.range,
        currentlyExcluded: false,
        cursorOffset: 7,
      );
      expect(result.text, '/!opened');
      expect(result.cursorOffset, 8);
    });

    test('toggling a category token works the same way, with "@"', () {
      final parsed = parseSearchQuery('@work');
      final result = toggleQueryToken(
        '@work',
        parsed.categoryTokens.single.range,
        currentlyExcluded: false,
        cursorOffset: 5,
      );
      expect(result.text, '@!work');
      expect(result.cursorOffset, 6);
    });
  });
}
