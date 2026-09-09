/// What a [TimeObject] represents on the timeline.
enum BlockKind {
  /// A concrete activity at a concrete time (e.g. breakfast, commute).
  anchor,

  /// A period during which attention belongs to one aspect of life,
  /// with no task list of its own (e.g. "work", "cleaning").
  frame,
}

/// A single block on the day timeline.
///
/// Both [BlockKind.anchor] and [BlockKind.frame] share this shape; they
/// differ only in meaning and in how they are rendered.
class TimeObject {
  /// Creates a [TimeObject].
  ///
  /// [start] and [end] must fall on the 15-minute grid, and [end] must be
  /// after [start].
  new({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.kind,
    required this.locked,
  }) : assert(_isOnGrid(start), 'start must be on the 15-minute grid'),
       assert(_isOnGrid(end), 'end must be on the 15-minute grid'),
       assert(end.isAfter(start), 'end must be after start');

  /// Unique identifier for this block.
  final String id;

  /// Short label shown on the block.
  final String title;

  /// When the block begins.
  final DateTime start;

  /// When the block ends.
  final DateTime end;

  /// Whether this is a concrete [BlockKind.anchor] or a [BlockKind.frame].
  final BlockKind kind;

  /// Whether this block must not move during replanning.
  final bool locked;

  static bool _isOnGrid(DateTime time) =>
      time.second == 0 &&
      time.millisecond == 0 &&
      time.microsecond == 0 &&
      time.minute % 15 == 0;
}
