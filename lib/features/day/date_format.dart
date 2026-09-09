const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Formats [date] as e.g. "Wednesday, September 9, 2026".
///
/// No `intl` dependency is needed for this fixed English format.
String formatDayLabel(DateTime date) {
  final weekday = _weekdays[date.weekday - 1];
  final month = _months[date.month - 1];
  return '$weekday, $month ${date.day}, ${date.year}';
}
