/// Returns the start (midnight) of the calendar week containing [date],
/// treating [firstDayOfWeek] (`DateTime.monday`..`DateTime.sunday`) as the
/// first day of that week.
DateTime startOfWeek(DateTime date, {required int firstDayOfWeek}) {
  final offset = (date.weekday - firstDayOfWeek + 7) % 7;
  final start = date.subtract(Duration(days: offset));
  return DateTime(start.year, start.month, start.day);
}

/// Whether [a] and [b] fall on the same calendar date, ignoring time of day.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
