import 'package:flutter/services.dart' show TextRange;

/// The only status word currently recognized — a task has no other
/// boolean field to filter by, so any other word after `/` is left
/// alone as plain search text rather than treated as a token.
const openedStatusWord = 'opened';

/// A `#tag`/`#!tag` occurrence found anywhere in a unified search query
/// string, together with the exact range of characters it occupies —
/// used to mutate exactly that range when toggled (see [toggleQueryToken])
/// and to know where to style it when rendering.
class TagToken {
  /// Creates a tag token.
  const new({required this.tag, required this.excluded, required this.range});

  /// The tag's lowercased name, without the leading '#'.
  final String tag;

  /// Whether this tag is excluded (prefixed with '!').
  final bool excluded;

  /// The exact range of characters this token occupies in the query.
  final TextRange range;
}

/// A `/opened`/`/!opened` occurrence — at most one is recognized per
/// query (see [parseSearchQuery]).
class StatusToken {
  /// Creates a status token.
  const new({required this.excluded, required this.range});

  /// Whether this status token is excluded (prefixed with '!').
  final bool excluded;

  /// The exact range of characters this token occupies in the query.
  final TextRange range;
}

/// The parsed pieces of a unified search query string: every tag token,
/// at most one status token, and the free text left over once every
/// recognized token's characters are removed.
class ParsedQuery {
  /// Creates a parsed query result.
  const new({
    required this.tagTokens,
    required this.statusToken,
    required this.freeText,
  });

  /// Every tag token found in the query, in order of appearance.
  final List<TagToken> tagTokens;

  /// The status token found in the query, if any (at most one).
  final StatusToken? statusToken;

  /// The remaining free text after all recognized tokens are removed,
  /// with whitespace normalized.
  final String freeText;
}

final _tokenPattern = RegExp(r'(#|/)(!?)(\w+)');

/// Parses [text] for every `#tag`/`#!tag` and the first `/opened`/
/// `/!opened` occurrence, returning their positions plus the leftover
/// free text (every recognized token's characters removed, whitespace
/// collapsed and trimmed).
///
/// A `/word` where `word` isn't [openedStatusWord] is left alone as
/// plain text. A second `/opened`/`/!opened` beyond the first is also
/// left as plain text: only one status filter slot exists.
ParsedQuery parseSearchQuery(String text) {
  final tagTokens = <TagToken>[];
  StatusToken? statusToken;
  final removedRanges = <TextRange>[];

  for (final match in _tokenPattern.allMatches(text)) {
    final symbol = match.group(1)!;
    final excluded = match.group(2) == '!';
    final word = match.group(3)!;
    final range = TextRange(start: match.start, end: match.end);
    if (symbol == '#') {
      tagTokens.add(
        TagToken(tag: word.toLowerCase(), excluded: excluded, range: range),
      );
      removedRanges.add(range);
    } else if (statusToken == null && word.toLowerCase() == openedStatusWord) {
      statusToken = StatusToken(excluded: excluded, range: range);
      removedRanges.add(range);
    }
  }

  final buffer = StringBuffer();
  var cursor = 0;
  for (final range in removedRanges) {
    buffer.write(text.substring(cursor, range.start));
    cursor = range.end;
  }
  buffer.write(text.substring(cursor));
  final freeText = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

  return ParsedQuery(
    tagTokens: tagTokens,
    statusToken: statusToken,
    freeText: freeText,
  );
}

/// Every recognized token in [parsed] (tag and status alike) as a
/// uniform `(range, excluded)` shape, sorted left-to-right — the order
/// rendering (and any other range-based consumer) needs.
List<({TextRange range, bool excluded})> orderedTokenRanges(
  ParsedQuery parsed,
) {
  final ranges = [
    for (final t in parsed.tagTokens) (range: t.range, excluded: t.excluded),
    if (parsed.statusToken != null)
      (
        range: parsed.statusToken!.range,
        excluded: parsed.statusToken!.excluded,
      ),
  ];
  return ranges..sort((a, b) => a.range.start.compareTo(b.range.start));
}

/// Returns [text] with the token at [range] toggled between its
/// included and excluded form (inserting/removing the `!` right after
/// the `#`/`/`), and the equivalent offset for [cursorOffset] once that
/// edit is applied (shifted by the token's change in length if the
/// cursor was positioned at or after the edit point, unchanged
/// otherwise).
({String text, int cursorOffset}) toggleQueryToken(
  String text,
  TextRange range, {
  required bool currentlyExcluded,
  required int cursorOffset,
}) {
  final bangIndex = range.start + 1;
  final String newText;
  final int delta;
  if (currentlyExcluded) {
    newText = text.replaceRange(bangIndex, bangIndex + 1, '');
    delta = -1;
  } else {
    newText = text.replaceRange(bangIndex, bangIndex, '!');
    delta = 1;
  }
  final newCursor = cursorOffset >= bangIndex
      ? cursorOffset + delta
      : cursorOffset;
  return (text: newText, cursorOffset: newCursor);
}
