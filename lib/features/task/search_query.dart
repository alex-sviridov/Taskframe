import 'package:flutter/services.dart' show TextRange;

/// The only status word currently recognized — [Task] has no other
/// boolean field to filter by, so any other word after `/` is left
/// alone as plain search text rather than treated as a token.
const openedStatusWord = 'opened';

/// A `#tag`/`#!tag` occurrence found anywhere in a unified search query
/// string, together with the exact range of characters it occupies —
/// used to mutate exactly that range when toggled ([toggleQueryToken])
/// and to know where to style it when rendering.
class TagToken {
  const TagToken({
    required this.tag,
    required this.excluded,
    required this.range,
  });

  final String tag;
  final bool excluded;
  final TextRange range;
}

/// A `/opened`/`/!opened` occurrence — at most one is recognized per
/// query (see [parseSearchQuery]).
class StatusToken {
  const StatusToken({required this.excluded, required this.range});

  final bool excluded;
  final TextRange range;
}

/// The parsed pieces of a unified search query string: every tag token,
/// at most one status token, and the free text left over once every
/// recognized token's characters are removed.
class ParsedQuery {
  const ParsedQuery({
    required this.tagTokens,
    required this.statusToken,
    required this.freeText,
  });

  final List<TagToken> tagTokens;
  final StatusToken? statusToken;
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
  ranges.sort((a, b) => a.range.start.compareTo(b.range.start));
  return ranges;
}
