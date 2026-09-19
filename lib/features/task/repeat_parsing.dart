const _wordToUnit = {
  'd': 'd',
  'day': 'd',
  'days': 'd',
  'w': 'w',
  'week': 'w',
  'weeks': 'w',
  'm': 'm',
  'month': 'm',
  'months': 'm',
  'y': 'y',
  'year': 'y',
  'years': 'y',
};

final _trailingRepeatPattern = RegExp(
  r'(^|\s)[Ee][Vv][Ee][Rr][Yy] (\d+)\s*([A-Za-z]+) $',
);
final _finalRepeatPattern = RegExp(
  r'(^|\s)[Ee][Vv][Ee][Rr][Yy] (\d+)\s*([A-Za-z]+)$',
);

/// If [text] ends with `every <n><unit>`/`every <n> <word>` immediately
/// followed by the space that was just typed, returns the normalized
/// compact repeat string (e.g. `"2w"`) and the title with that
/// `every ...` chunk removed. Returns `null` when there is no such
/// trailing repeat, or the unit isn't recognized (see [_wordToUnit]).
({String title, String repeat})? extractTrailingRepeat(String text) =>
    _extract(text, _trailingRepeatPattern);

/// If [text] ends with `every <n><unit>`/`every <n> <word>` with nothing
/// after it (no trailing space needed) — the case where the user typed a
/// repeat and left/closed the field without ever typing a following
/// space — returns the normalized compact repeat string and the title
/// with that `every ...` chunk removed. Returns `null` when there is no
/// such repeat at the very end.
({String title, String repeat})? extractFinalRepeat(String text) =>
    _extract(text, _finalRepeatPattern);

({String title, String repeat})? _extract(String text, RegExp pattern) {
  final match = pattern.firstMatch(text);
  if (match == null) return null;
  final count = match.group(2)!;
  final unit = _wordToUnit[match.group(3)!.toLowerCase()];
  if (unit == null) return null;
  return (
    title: text.substring(0, match.start) + match.group(1)!,
    repeat: '$count$unit',
  );
}

/// Returns [from] advanced by [repeat] (a compact `<n><unit>` string, as
/// produced by [extractTrailingRepeat]/[extractFinalRepeat]) — days and
/// weeks add a fixed [Duration]; months and years add calendar
/// months/years (so "1m" from Jan 31 lands wherever [DateTime]
/// normalizes an out-of-range day to, same as date parsing elsewhere in
/// this feature).
DateTime nextOccurrence(DateTime from, String repeat) {
  final match = RegExp(r'^(\d+)([dwmy])$').firstMatch(repeat)!;
  final count = int.parse(match.group(1)!);
  final unit = match.group(2)!;
  return switch (unit) {
    'd' => from.add(Duration(days: count)),
    'w' => from.add(Duration(days: count * 7)),
    'm' => DateTime(
      from.year,
      from.month + count,
      from.day,
      from.hour,
      from.minute,
      from.second,
      from.millisecond,
      from.microsecond,
    ),
    'y' => DateTime(
      from.year + count,
      from.month,
      from.day,
      from.hour,
      from.minute,
      from.second,
      from.millisecond,
      from.microsecond,
    ),
    _ => throw StateError('Unreachable: unit is validated by the regex'),
  };
}
