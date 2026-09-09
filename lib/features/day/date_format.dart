const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Formats [date] using [pattern], a template built from the tokens `dd`
/// (zero-padded day), `MM` (zero-padded month), and `yyyy` (4-digit year),
/// e.g. `'dd/MM/yyyy'` or `'MM/dd/yyyy'`.
String formatDate(DateTime date, String pattern) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');

  return pattern
      .replaceAll('dd', day)
      .replaceAll('MM', month)
      .replaceAll('yyyy', year);
}

/// Formats [date] for a schedule header: with its weekday name prefixed
/// (e.g. `"Wednesday, 09/09/2026"`) when [showWeekday] is true, or just the
/// formatted date (e.g. `"09/09/2026"`) when it's false.
String formatDayHeaderLabel(
  DateTime date, {
  required bool showWeekday,
  required String pattern,
}) {
  final formatted = formatDate(date, pattern);
  if (!showWeekday) return formatted;

  final weekday = _weekdays[date.weekday - 1];
  return '$weekday, $formatted';
}
