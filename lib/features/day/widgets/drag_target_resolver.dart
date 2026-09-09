import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';

/// The stable [GlobalKey] a `DayGrid` for [date] is built with, so
/// [resolveDragTarget] can find its render box regardless of which page
/// or column a drag started in.
GlobalKey dayGridKeyFor(DateTime date) => GlobalObjectKey(date);

/// Finds which of [pageDates]' day columns [globalPosition] currently
/// falls over, and the 15-minute slot within it, by looking up each
/// date's mounted widget via [dayGridKeyFor].
///
/// Returns `null` if [globalPosition] isn't over any of [pageDates]'
/// columns.
({DateTime date, DateTime start})? resolveDragTarget({
  required Offset globalPosition,
  required List<DateTime> pageDates,
  required DaySettings settings,
  required double slotHeight,
}) {
  for (final date in pageDates) {
    final renderObject = dayGridKeyFor(
      date,
    ).currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) continue;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    if (!rect.contains(globalPosition)) continue;

    final start = slotStartForOffset(
      day: date,
      dy: globalPosition.dy - topLeft.dy,
      settings: settings,
      slotHeight: slotHeight,
    );
    if (start == null) continue;

    return (date: date, start: start);
  }
  return null;
}
