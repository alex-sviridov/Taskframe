/// Formats [date] as a zero-padded `yyyy-MM-dd` string, ignoring its
/// time-of-day component. Used as the `dateKey` field on stored day
/// blocks, so `SembastDayBlocksRepository.load` can query "every block on
/// this calendar date" without relying on `DateTime` equality (which
/// would also compare hours/minutes).
String dateKeyFor(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
