import 'package:flutter/widgets.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';

/// One [GlobalKey] per [ScheduleColumn], handed out by [scheduleGridKeyFor].
final Map<ScheduleColumn, GlobalKey> _scheduleGridKeys =
    <ScheduleColumn, GlobalKey>{};

/// The [GlobalKey] a `DayGrid` for [column] is built with, so
/// [resolveDragTarget] can find its render box regardless of which page or
/// screen a drag started in.
///
/// Memoized per [column] — [DayColumn]'s own equality already normalizes
/// to calendar day, so callers may rebuild their column lists with fresh
/// (but `==`-equal) values on every build without changing the key.
///
/// Do not "simplify" this back to `GlobalObjectKey(column)`: that key
/// type's equality is `identical(other.value, value)`, so a freshly
/// constructed (but `==`-equal) [ScheduleColumn] yields a key that
/// compares *unequal* to the previous build's, making `Widget.canUpdate`
/// return false and forcing Flutter to destroy and reinflate the whole
/// `DayGrid` element — losing its open draft and now-timer — on every
/// rebuild.
GlobalKey scheduleGridKeyFor(ScheduleColumn column) {
  _schedulePrune();
  return _scheduleGridKeys.putIfAbsent(column, GlobalKey.new);
}

/// Whether a prune sweep has already been scheduled for the current
/// frame, so a page with many columns doesn't queue one callback per
/// [scheduleGridKeyFor] call.
bool _pruneScheduled = false;

/// Queues [_pruneUnmountedKeys] to run once, after the current frame
/// finishes.
///
/// Deferred to a post-frame callback rather than run inline: a page
/// building several columns (e.g. a week view's 7 dates) calls
/// [scheduleGridKeyFor] once per column in the same synchronous build,
/// before any of that frame's widgets have mounted — pruning inline right
/// then would see every one of those brand-new keys as still
/// `currentContext == null` and wrongly discard them before they ever get
/// the chance to attach. By the end of the frame, every key requested
/// during it is either mounted (kept) or was never actually built (safe
/// to drop).
void _schedulePrune() {
  if (_pruneScheduled) return;
  _pruneScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _pruneScheduled = false;
    _pruneUnmountedKeys();
  });
}

/// Drops every memoized key whose `DayGrid` has since unmounted, so a long
/// session paging through many columns doesn't grow [_scheduleGridKeys]
/// forever.
void _pruneUnmountedKeys() {
  _scheduleGridKeys.removeWhere((_, key) => key.currentContext == null);
}

/// The number of columns currently memoized in [_scheduleGridKeys].
@visibleForTesting
int scheduleGridKeyCacheSizeForTest() => _scheduleGridKeys.length;

/// Finds which column [globalPosition] currently falls over, and the
/// 15-minute slot within it, by looking up each candidate column's
/// mounted widget via [scheduleGridKeyFor].
///
/// [origin] is the column the dragged/resized block started in, and only
/// candidates of the *same* [ScheduleColumn] variant can match it: a drag
/// begun on a [TemplateColumn] can only ever land on another
/// [TemplateColumn], and likewise for [DayColumn]. Mounted-and-attached is
/// not a strong enough filter on its own — `StatefulShellRoute.indexedStack`
/// lays out every branch's widget tree even while it is offstage
/// (`Offstage` skips painting and hit-testing but not layout, and
/// `IndexedStack` lays every child out at the same origin), so once both
/// `/` and `/templates` have been visited their `DayGrid`s report
/// overlapping global rects and a rect test alone would happily resolve
/// the invisible other branch's column. Landing on the wrong variant is not
/// merely a misplaced drop: each controller casts its columns to the
/// variant it owns, so a cross-variant target crashes.
///
/// [candidateColumns] defaults to every column [scheduleGridKeyFor] has
/// ever been asked for, narrowed by the [origin] variant rule above. Pass
/// it explicitly only to restrict the search further (tests do); the
/// variant rule still applies to whatever is passed.
///
/// Returns `null` if [globalPosition] isn't over any mounted column of
/// [origin]'s variant, or if it's over such a column but a block of
/// [blockDuration] dropped at the snapped slot there would end after that
/// column's boundary — see [dayEndFor]. Either way, the caller's existing
/// "no valid column" fallback (previewing the snap-back at the block's own
/// original position) applies.
({ScheduleColumn column, DateTime start})? resolveDragTarget({
  required Offset globalPosition,
  required ScheduleColumn origin,
  required DaySettings settings,
  required double slotHeight,
  required Duration blockDuration,
  List<ScheduleColumn>? candidateColumns,
}) {
  final columns =
      candidateColumns ?? _scheduleGridKeys.keys.toList(growable: false);
  for (final column in columns) {
    if (!_sameVariant(column, origin)) continue;

    final renderObject = scheduleGridKeyFor(column).currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) continue;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    if (!rect.contains(globalPosition)) continue;

    final anchor = anchorDateFor(column);
    final start = slotStartForOffset(
      day: anchor,
      dy: globalPosition.dy - topLeft.dy,
      settings: settings,
      slotHeight: slotHeight,
    );
    if (start == null) continue;
    if (start.add(blockDuration).isAfter(dayEndFor(anchor, settings))) {
      continue;
    }

    return (column: column, start: start);
  }
  return null;
}

/// Whether [column] is the same [ScheduleColumn] variant as [origin], and
/// so a legal drag target for a block that started in [origin].
bool _sameVariant(ScheduleColumn column, ScheduleColumn origin) =>
    switch (origin) {
      DayColumn() => column is DayColumn,
      TemplateColumn() => column is TemplateColumn,
    };
