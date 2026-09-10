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
/// A new block's start must fall strictly within the grid — [slotStartForOffset]
/// rejects the day's exact end because nothing could start there. A resize's
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
