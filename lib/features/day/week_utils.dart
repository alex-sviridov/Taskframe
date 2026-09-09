/// Returns the start (midnight) of the calendar week containing [date],
/// treating [firstDayOfWeek] (`DateTime.monday`..`DateTime.sunday`) as the
/// first day of that week.
DateTime startOfWeek(DateTime date, {required int firstDayOfWeek}) {
  final offset = (date.weekday - firstDayOfWeek + 7) % 7;
  final start = date.subtract(Duration(days: offset));
  return DateTime(start.year, start.month, start.day);
}
