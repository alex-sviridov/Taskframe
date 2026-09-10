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
GlobalKey dayGridKeyFor(DateTime date) {
  _schedulePrune();
  return _dayGridKeys.putIfAbsent(_calendarDay(date), GlobalKey.new);
}

/// Whether a prune sweep has already been scheduled for the current frame,
/// so a page with many columns (e.g. a 7-day week view) doesn't queue one
/// callback per [dayGridKeyFor] call.
bool _pruneScheduled = false;

/// Queues [_pruneUnmountedKeys] to run once, after the current frame
/// finishes.
///
/// Deferred to a post-frame callback rather than run inline: a page
/// building several columns (e.g. a week view's 7 dates) calls
/// [dayGridKeyFor] once per column in the same synchronous build, before
/// any of that frame's widgets have mounted — pruning inline right then
/// would see every one of those brand-new keys as still `currentContext ==
/// null` and wrongly discard them before they ever get the chance to
/// attach. By the end of the frame, every key requested during it is either
/// mounted (kept) or was never actually built (safe to drop).
void _schedulePrune() {
  if (_pruneScheduled) return;
  _pruneScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _pruneScheduled = false;
    _pruneUnmountedKeys();
  });
}

/// Drops every memoized key whose `DayGrid` has since unmounted, so a long
/// session paging through many calendar days doesn't grow [_dayGridKeys]
/// forever.
///
/// Safe to call once every frame's widgets have settled: a key still
/// attached to a mounted element (in particular, every currently visible
/// day) always has a non-null [GlobalKey.currentContext] and so is never
/// touched, preserving the one-key-per-calendar-day identity documented on
/// [dayGridKeyFor].
void _pruneUnmountedKeys() {
  _dayGridKeys.removeWhere((_, key) => key.currentContext == null);
}

/// The number of dates currently memoized in [_dayGridKeys].
@visibleForTesting
int dayGridKeyCacheSizeForTest() => _dayGridKeys.length;

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
/// Returns `null` if [globalPosition] isn't over any mounted column, or if
/// it's over a column but a block of [blockDuration] dropped at the snapped
/// slot there would end after that day's boundary — [slotStartForOffset]
/// only keeps a *start* within the grid, so without this a long block
/// dragged near the day's end could land with its end past midnight (see
/// [dayEndFor]), which the grid then renders with a corrupted, negative
/// height because it reads a wrapped-around time as if it belonged to the
/// same day. Either way, the caller's existing "no valid column" fallback
/// (previewing the snap-back at the block's own original position) applies.
({DateTime date, DateTime start})? resolveDragTarget({
  required Offset globalPosition,
  required DaySettings settings,
  required double slotHeight,
  required Duration blockDuration,
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
    if (start.add(blockDuration).isAfter(dayEndFor(date, settings))) continue;

    return (date: date, start: start);
  }
  return null;
}
