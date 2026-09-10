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
    return DateTime(day.year, day.month, day.day, settings.dayEndHour);
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
/// occupied by one of [existingBlocks].
Duration durationForNewBlock({
  required DateTime slotStart,
  required List<TimeObject> existingBlocks,
}) {
  final nextSlotStart = slotStart.add(const Duration(minutes: 15));
  final nextSlotEnd = slotStart.add(_defaultDuration);

  final nextSlotTaken = existingBlocks.any(
    (block) =>
        block.start.isBefore(nextSlotEnd) && block.end.isAfter(nextSlotStart),
  );

  return nextSlotTaken ? _shrunkDuration : _defaultDuration;
}
