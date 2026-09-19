import 'package:taskframe/features/day/models/time_object.dart';

/// The four event slots the "Now" view shows for one day, relative to
/// `now`. Any slot is `null` when there's nothing to show in it.
class NowSelection {
  /// Creates a [NowSelection].
  const new({this.previous, this.current, this.next1, this.next2});

  /// The most recently ended block before [current]'s start.
  final TimeObject? previous;

  /// The block covering `now`, or — when nothing does — the nearest
  /// upcoming block, borrowed into this slot.
  final TimeObject? current;

  /// The block immediately after [current] in start-time order.
  final TimeObject? next1;

  /// The block after [next1] in start-time order.
  final TimeObject? next2;
}

/// Picks [NowSelection]'s four slots out of [blocks] (assumed to all be
/// on the same day) relative to [now].
///
/// "Current" is whichever block covers `now`; if several overlap, the one
/// with the latest start wins (the most specific/innermost one). If none
/// covers `now`, the nearest upcoming block is borrowed as "current"
/// instead. If there's no upcoming block either (the day is over),
/// "current" and both "next" slots are empty, and "previous" is simply
/// the day's last block.
NowSelection selectNowEvents(List<TimeObject> blocks, DateTime now) {
  final sorted = [...blocks]..sort((a, b) => a.start.compareTo(b.start));

  final covering = [
    for (final b in sorted)
      if (!b.start.isAfter(now) && b.end.isAfter(now)) b,
  ];
  TimeObject? current;
  if (covering.isNotEmpty) {
    current = covering.reduce((a, b) => b.start.isAfter(a.start) ? b : a);
  } else {
    final upcoming = sorted.where((b) => b.start.isAfter(now));
    current = upcoming.isEmpty ? null : upcoming.first;
  }

  final previous = current == null
      ? (sorted.isEmpty ? null : sorted.last)
      : _lastEndingBefore(sorted, current.start);

  final after = current == null
      ? const <TimeObject>[]
      : sorted.where((b) => b.start.isAfter(current!.start)).toList();

  return NowSelection(
    previous: previous,
    current: current,
    next1: after.isNotEmpty ? after[0] : null,
    next2: after.length > 1 ? after[1] : null,
  );
}

TimeObject? _lastEndingBefore(List<TimeObject> sorted, DateTime start) {
  TimeObject? best;
  for (final b in sorted) {
    if (!b.end.isAfter(start) && (best == null || b.end.isAfter(best.end))) {
      best = b;
    }
  }
  return best;
}
