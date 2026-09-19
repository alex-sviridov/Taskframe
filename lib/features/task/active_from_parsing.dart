/// Formats [date] as `dd/mm/yy`, the format [extractTrailingActiveFrom]/
/// [extractFinalActiveFrom] parse back out of a title.
String formatActiveFrom(DateTime date) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  return '${twoDigits(date.day)}/${twoDigits(date.month)}/'
      '${twoDigits(date.year % 100)}';
}

final _trailingActiveFromPattern = RegExp(
  r'(^|\s)[Ff][Rr][Oo][Mm] (\d{1,2})/(\d{1,2})(?:/(\d{2,4}))? $',
);
final _finalActiveFromPattern = RegExp(
  r'(^|\s)[Ff][Rr][Oo][Mm] (\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?$',
);

/// If [text] ends with `from dd/mm[/yy[yy]]` immediately followed by the
/// space that was just typed, returns the parsed date and the title with
/// that `from ...` chunk removed. A missing year defaults to the current
/// year; a two-digit year is read as `20yy`. Returns `null` when there is
/// no such trailing date, or the day/month don't form a valid date.
({String title, DateTime activeFrom})? extractTrailingActiveFrom(String text) =>
    _extract(text, _trailingActiveFromPattern);

/// If [text] ends with `from dd/mm[/yy[yy]]` with nothing after it (no
/// trailing space needed) — the case where the user typed a date and
/// left/closed the field without ever typing a following space — returns
/// the parsed date and the title with that `from ...` chunk removed.
/// Returns `null` when there is no such date at the very end.
({String title, DateTime activeFrom})? extractFinalActiveFrom(String text) =>
    _extract(text, _finalActiveFromPattern);

({String title, DateTime activeFrom})? _extract(String text, RegExp pattern) {
  final match = pattern.firstMatch(text);
  if (match == null) return null;
  final day = int.parse(match.group(2)!);
  final month = int.parse(match.group(3)!);
  final yearGroup = match.group(4);
  final year = yearGroup == null
      ? DateTime.now().year
      : yearGroup.length <= 2
      ? 2000 + int.parse(yearGroup)
      : int.parse(yearGroup);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return (
    title: text.substring(0, match.start) + match.group(1)!,
    activeFrom: date,
  );
}
