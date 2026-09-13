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

    test('/other (not "opened") is left entirely as plain text', () {
      final parsed = parseSearchQuery('/other');
      expect(parsed.statusToken, isNull);
      expect(parsed.tagTokens, isEmpty);
      expect(parsed.freeText, '/other');
    });

    test('a mixed query extracts tags and status, collapsing the '
        'remaining whitespace into single spaces', () {
      final parsed = parseSearchQuery('Buy milk #groceries /opened extra');
      expect(parsed.tagTokens.map((t) => t.tag), ['groceries']);
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
  });
}
