import 'package:flutter/widgets.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';

/// One [GlobalKey] per calendar day, handed out by [dayGridKeyFor].
///
/// Keyed by a midnight-normalized [DateTime], which is safe because
/// [DateTime] has real value equality and `hashCode`.
final Map<DateTime, GlobalKey> _dayGridKeys = <DateTime, GlobalKey>{};

DateTime _calendarDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

/// The [GlobalKey] a `DayGrid` for [date] is built with, so
/// [resolveDragTarget] can find its render box regardless of which page or
/// column a drag started in.
///
/// The key is memoized per calendar day: every call for the same
/// year/month/day returns the *same* [GlobalKey] instance, so callers may
/// rebuild their date lists with fresh [DateTime] objects on every build
/// without changing the key.
///
/// Do not "simplify" this back to `GlobalObjectKey(date)`: that key type's
/// equality is `identical(other.value, value)`, so a freshly-constructed
/// (but `==`-equal) [DateTime] yields a key that compares *unequal* to the
/// previous build's, making `Widget.canUpdate` return false and forcing
/// Flutter to destroy and reinflate the whole `DayGrid` element — losing its
/// open draft and now-timer — on every rebuild.
GlobalKey dayGridKeyFor(DateTime date) =>
    _dayGridKeys.putIfAbsent(_calendarDay(date), GlobalKey.new);

/// Finds which day column [globalPosition] currently falls over, and the
/// 15-minute slot within it, by looking up each candidate date's mounted
/// widget via [dayGridKeyFor].
///
/// [candidateDates] defaults to *every* calendar day [dayGridKeyFor] has
/// ever been asked for; only the handful whose `DayGrid` is mounted and
/// attached right now can match, so the result always reflects whatever
/// page is visible at the moment of the call rather than whatever was
/// visible when a drag started. Pass [candidateDates] explicitly only to
/// restrict the search (tests do).
///
/// Returns `null` if [globalPosition] isn't over any mounted column.
({DateTime date, DateTime start})? resolveDragTarget({
  required Offset globalPosition,
  required DaySettings settings,
  required double slotHeight,
  List<DateTime>? candidateDates,
}) {
  final dates = candidateDates ?? _dayGridKeys.keys.toList(growable: false);
  for (final date in dates) {
    final renderObject = dayGridKeyFor(date).currentContext?.findRenderObject();
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
