/// Identifies which column of a schedule grid a block belongs to — a
/// calendar day, or a template — independent of the `DateTime` a
/// [TimeObject] uses for its time-of-day, which for a template block
/// always carries [templateAnchorDate] and means nothing on its own: the
/// column identity is this type, never a block's own date.
sealed class ScheduleColumn {
  const ScheduleColumn();
}

/// A real calendar day. Equality and hashing are by calendar day
/// (year/month/day), ignoring time of day, so callers may pass a freshly
/// constructed but same-day [DateTime] without changing identity — the
/// same guarantee `dayGridKeyFor`'s docs used to describe directly.
class DayColumn extends ScheduleColumn {
  const DayColumn(this.date);

  final DateTime date;

  @override
  bool operator ==(Object other) =>
      other is DayColumn &&
      other.date.year == date.year &&
      other.date.month == date.month &&
      other.date.day == date.day;

  @override
  int get hashCode => Object.hash(date.year, date.month, date.day);

  @override
  String toString() => 'DayColumn($date)';
}

/// One template, identified by [templateId].
class TemplateColumn extends ScheduleColumn {
  const TemplateColumn(this.templateId);

  final String templateId;

  @override
  bool operator ==(Object other) =>
      other is TemplateColumn && other.templateId == templateId;

  @override
  int get hashCode => templateId.hashCode;

  @override
  String toString() => 'TemplateColumn($templateId)';
}

/// The fixed date every template block's `start`/`end` carries as their
/// date component. Never read as meaning anything — a template block's
/// column identity is its [TemplateColumn], not this date. Exists purely
/// so [TimeObject] can keep using `DateTime` for time-of-day arithmetic
/// without a template needing a real calendar date.
final DateTime templateAnchorDate = DateTime(2000, 1, 1);

/// The `DateTime` the grid-math helpers in `day_new_block.dart` should
/// anchor to for [column]: the real date for a [DayColumn], or
/// [templateAnchorDate] for a [TemplateColumn].
DateTime anchorDateFor(ScheduleColumn column) => switch (column) {
  DayColumn(:final date) => date,
  TemplateColumn() => templateAnchorDate,
};
