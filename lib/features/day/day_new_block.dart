import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// The start of a new block's default duration before checking for
/// conflicts with existing blocks.
const _defaultDuration = Duration(minutes: 30);

/// The duration a new block shrinks to when its default duration would
/// overlap an existing block.
const _shrunkDuration = Duration(minutes: 15);

/// Finds the 15-minute grid slot a tap at [dy] pixels from the top of the
/// day grid falls into, returning its start time on [day].
///
/// Returns `null` if [dy] falls outside the grid defined by [settings].
DateTime? slotStartForOffset({
  required DateTime day,
  required double dy,
  required DaySettings settings,
  required double slotHeight,
}) {
  if (dy < 0) return null;

  final slotIndex = dy ~/ slotHeight;
  final slotCount = (settings.dayEndHour - settings.dayStartHour) * 4;
  if (slotIndex >= slotCount) return null;

  final minutesFromStart = slotIndex * 15;
  final totalMinutes = settings.dayStartHour * 60 + minutesFromStart;
  return DateTime(
    day.year,
    day.month,
    day.day,
    totalMinutes ~/ 60,
    totalMinutes % 60,
  );
}

/// The day's exact end-of-grid boundary for [day] under [settings] — e.g.
/// `2026-09-09 23:00` when `dayEndHour: 23`. Nothing on [day]'s grid may
/// ever end after this instant.
DateTime dayEndFor(DateTime day, DaySettings settings) =>
    DateTime(day.year, day.month, day.day, settings.dayEndHour);

/// Resolves a resize drag's candidate time from [dy] pixels down the grid,
/// like [slotStartForOffset] but clamped to the day's own start/end instead
/// of returning `null` there.
///
/// A new block's start must fall strictly within the grid —
/// [slotStartForOffset] rejects the day's exact end because nothing could
/// start there. A resize's
/// dragged edge has no such restriction: the block's end (or start) should be
/// able to reach the day's exact boundary, not stop one 15-minute slot short
/// of it.
DateTime resizeCandidateForOffset({
  required DateTime day,
  required double dy,
  required DaySettings settings,
  required double slotHeight,
}) {
  final slotCount = (settings.dayEndHour - settings.dayStartHour) * 4;
  final totalHeight = slotCount * slotHeight;
  final clampedDy = dy.clamp(0, totalHeight).toDouble();
  if (clampedDy >= totalHeight) {
    return dayEndFor(day, settings);
  }
  return slotStartForOffset(
    day: day,
    dy: clampedDy,
    settings: settings,
    slotHeight: slotHeight,
  )!;
}

/// The duration a new block starting at [slotStart] should get: 30 minutes
/// by default, or 15 minutes if the following 15-minute slot is already
/// occupied by one of [existingBlocks] — further shrunk so the block never
/// ends after [settings]'s day boundary, for a [slotStart] close enough to
/// it that even 15 minutes would overshoot.
///
/// [slotStart] is assumed to already be a valid grid slot (see
/// [slotStartForOffset]), which guarantees at least 15 minutes remain before
/// the day end, so the result is never shorter than that.
Duration durationForNewBlock({
  required DateTime slotStart,
  required List<TimeObject> existingBlocks,
  required DaySettings settings,
}) {
  final nextSlotStart = slotStart.add(const Duration(minutes: 15));
  final nextSlotEnd = slotStart.add(_defaultDuration);

  final nextSlotTaken = existingBlocks.any(
    (block) => block.overlaps(nextSlotStart, nextSlotEnd),
  );

  final duration = nextSlotTaken ? _shrunkDuration : _defaultDuration;
  final remaining = dayEndFor(slotStart, settings).difference(slotStart);
  return duration < remaining ? duration : remaining;
}

/// The `[start, end)` range a new block being drawn by dragging should span,
/// given the fixed point where the drag began ([anchor]) and where the
/// pointer currently is ([candidate]) — both already resolved to grid slots
/// (see [slotStartForOffset]/[resizeCandidateForOffset]). The block always
/// spans between the two, in whichever order they land, extended to at
/// least [_minEditDuration] when the drag hasn't moved far enough yet —
/// forward from [anchor] normally, or backward when forward would run past
/// the day's own end.
({DateTime start, DateTime end}) draftRangeForDrag({
  required DateTime anchor,
  required DateTime candidate,
  required DateTime day,
  required DaySettings settings,
}) {
  var start = anchor.isBefore(candidate) ? anchor : candidate;
  var end = anchor.isBefore(candidate) ? candidate : anchor;

  if (end.difference(start) < _minEditDuration) {
    final dayEnd = dayEndFor(day, settings);
    final extendedEnd = start.add(_minEditDuration);
    if (!extendedEnd.isAfter(dayEnd)) {
      end = extendedEnd;
    } else {
      start = end.subtract(_minEditDuration);
    }
  }

  return (start: start, end: end);
}

/// The first [duration]-long free gap on [day], searching forward from
/// [settings]'s day start through [existingBlocks] (sorted by start here
/// regardless of the order given) and returning the first gap between two
/// consecutive blocks (or before the first, or after the last) at least
/// [duration] long.
///
/// Falls back to right after the last block if no gap that long exists
/// anywhere on the day, even though the caller then has less than
/// [duration] of room left before the day end — callers should clamp the
/// resulting block's end to [dayEndFor], the same way [durationForNewBlock]
/// does for a manually-placed block.
DateTime findNextFreeSlot({
  required DateTime day,
  required List<TimeObject> existingBlocks,
  required DaySettings settings,
  required Duration duration,
}) {
  final sorted = [...existingBlocks]
    ..sort((a, b) => a.start.compareTo(b.start));

  var cursor = DateTime(day.year, day.month, day.day, settings.dayStartHour);
  for (final block in sorted) {
    if (block.start.difference(cursor) >= duration) {
      return cursor;
    }
    if (block.end.isAfter(cursor)) {
      cursor = block.end;
    }
  }
  return cursor;
}

/// The shortest a block may ever be edited down to — mirrors the day
/// screen's own resize-minimum, since both express the same "a block must
/// keep at least this much duration" rule.
const _minEditDuration = Duration(minutes: 15);

/// The contiguous range [block]'s start (if [editingStart]) or end
/// (otherwise) may move within, bounded by [block]'s nearest neighbor in
/// [others] on that side (or [settings]'s day start/end when there is
/// none) and by [_minEditDuration] against [block]'s own fixed edge.
///
/// [others] need not be pre-sorted or pre-filtered to exclude [block]
/// itself — only the nearest block ending at or before [block]'s start
/// (for [editingStart]) or starting at or after [block]'s end (otherwise)
/// affects the result, so every other entry is ignored.
({DateTime start, DateTime end}) validEditRange({
  required TimeObject block,
  required bool editingStart,
  required DateTime day,
  required DaySettings settings,
  required List<TimeObject> others,
}) {
  if (editingStart) {
    final previousEnd = others
        .where((b) => !b.end.isAfter(block.start))
        .map((b) => b.end)
        .fold<DateTime?>(
          null,
          (latest, end) => latest == null || end.isAfter(latest) ? end : latest,
        );
    return (
      start:
          previousEnd ??
          DateTime(day.year, day.month, day.day, settings.dayStartHour),
      end: block.end.subtract(_minEditDuration),
    );
  }

  final nextStart = others
      .where((b) => !b.start.isBefore(block.end))
      .map((b) => b.start)
      .fold<DateTime?>(
        null,
        (earliest, start) =>
            earliest == null || start.isBefore(earliest) ? start : earliest,
      );
  return (
    start: block.start.add(_minEditDuration),
    end: nextStart ?? dayEndFor(day, settings),
  );
}

/// Whether editing a block to span `[start, end)` on [day] is allowed: the
/// range must be ordered, fall within [settings]'s day bounds, and not
/// overlap any of [others]. Used to silently reject an invalid title/start/
/// end edit rather than showing an error.
bool isValidBlockEdit({
  required DateTime start,
  required DateTime end,
  required DaySettings settings,
  required DateTime day,
  required List<TimeObject> others,
}) {
  if (!end.isAfter(start)) return false;
  final dayStart = DateTime(
    day.year,
    day.month,
    day.day,
    settings.dayStartHour,
  );
  if (start.isBefore(dayStart)) return false;
  if (end.isAfter(dayEndFor(day, settings))) return false;
  return others.every((block) => !block.overlaps(start, end));
}

/// How far a postpone swipe shifts (or shrinks) a block.
const _postponeStep = Duration(minutes: 15);

/// The `[start, end)` range [block] should move to for a postpone swipe on
/// [day], or `null` if the swipe has nowhere valid to go.
///
/// Normally shifts both [block]'s start and end by [_postponeStep] — forward
/// for [toFuture], backward otherwise. If that full shift would overlap one
/// of [others] or run past the day's bounds (see [isValidBlockEdit]), falls
/// back to moving only the edge in the swipe's direction (the start for
/// [toFuture], the end otherwise), shrinking the block by [_postponeStep]
/// instead. Returns `null` if even that shrunk edit is invalid, e.g. the
/// block is already at the minimum duration with a barrier on that side.
({DateTime start, DateTime end})? postponeRange({
  required TimeObject block,
  required bool toFuture,
  required DateTime day,
  required DaySettings settings,
  required List<TimeObject> others,
}) {
  final delta = toFuture ? _postponeStep : -_postponeStep;
  final fullStart = block.start.add(delta);
  final fullEnd = block.end.add(delta);
  if (isValidBlockEdit(
    start: fullStart,
    end: fullEnd,
    settings: settings,
    day: day,
    others: others,
  )) {
    return (start: fullStart, end: fullEnd);
  }

  final partialStart = toFuture ? fullStart : block.start;
  final partialEnd = toFuture ? block.end : fullEnd;
  if (isValidBlockEdit(
    start: partialStart,
    end: partialEnd,
    settings: settings,
    day: day,
    others: others,
  )) {
    return (start: partialStart, end: partialEnd);
  }

  return null;
}

/// Whether copying [block] to [nextDate] (same time of day, same duration)
/// would overlap any of [nextDayBlocks].
bool copyToNextDayWouldOverlap({
  required TimeObject block,
  required DateTime nextDate,
  required List<TimeObject> nextDayBlocks,
}) {
  final duration = block.end.difference(block.start);
  final start = DateTime(
    nextDate.year,
    nextDate.month,
    nextDate.day,
    block.start.hour,
    block.start.minute,
  );
  final end = start.add(duration);
  return nextDayBlocks.any((b) => b.overlaps(start, end));
}
