import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);
const _slotHeight = 16.0;

void main() {
  group('slotStartForOffset', () {
    test('floors to the enclosing 15-minute slot', () {
      final start = slotStartForOffset(
        day: DateTime(2026, 9, 9),
        dy: 12 * _slotHeight + 5,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      // 12 slots after a 6:00 start is 9:00.
      expect(start, DateTime(2026, 9, 9, 9));
    });

    test('returns null above the grid', () {
      final start = slotStartForOffset(
        day: DateTime(2026, 9, 9),
        dy: -1,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(start, isNull);
    });

    test('returns null at or past the last slot', () {
      final lastSlot = (_settings.dayEndHour - _settings.dayStartHour) * 4 - 1;

      final start = slotStartForOffset(
        day: DateTime(2026, 9, 9),
        dy: (lastSlot + 1) * _slotHeight,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(start, isNull);
    });
  });

  group('resizeCandidateForOffset', () {
    test('matches slotStartForOffset within the grid', () {
      final candidate = resizeCandidateForOffset(
        day: DateTime(2026, 9, 9),
        dy: 12 * _slotHeight + 5,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      // 12 slots after a 6:00 start is 9:00.
      expect(candidate, DateTime(2026, 9, 9, 9));
    });

    test('clamps to the day start instead of returning null above the '
        'grid', () {
      final candidate = resizeCandidateForOffset(
        day: DateTime(2026, 9, 9),
        dy: -1,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(candidate, DateTime(2026, 9, 9, 6));
    });

    test('reaches the exact day end instead of stopping one slot short', () {
      final slotCount = (_settings.dayEndHour - _settings.dayStartHour) * 4;

      final candidate = resizeCandidateForOffset(
        day: DateTime(2026, 9, 9),
        dy: slotCount * _slotHeight,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(candidate, DateTime(2026, 9, 9, _settings.dayEndHour));
    });

    test('clamps to the day end for any offset past the grid', () {
      final slotCount = (_settings.dayEndHour - _settings.dayStartHour) * 4;

      final candidate = resizeCandidateForOffset(
        day: DateTime(2026, 9, 9),
        dy: (slotCount + 5) * _slotHeight,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(candidate, DateTime(2026, 9, 9, _settings.dayEndHour));
    });
  });

  group('durationForNewBlock', () {
    test('defaults to 30 minutes when both slots are free', () {
      final duration = durationForNewBlock(
        slotStart: DateTime(2026, 9, 9, 9),
        existingBlocks: const [],
        settings: _settings,
      );

      expect(duration, const Duration(minutes: 30));
    });

    test('shrinks to 15 minutes when the next slot is already taken', () {
      final duration = durationForNewBlock(
        slotStart: DateTime(2026, 9, 9, 9),
        existingBlocks: [
          TimeObject(
            id: '1',
            title: 'Work',
            start: DateTime(2026, 9, 9, 9, 15),
            end: DateTime(2026, 9, 9, 13),
            kind: BlockKind.frame,
            locked: false,
          ),
        ],
        settings: _settings,
      );

      expect(duration, const Duration(minutes: 15));
    });

    test('shrinks below 15 minutes when starting one slot before day end '
        'would otherwise overshoot it', () {
      // Day ends at 23:00; the last valid slot start is 22:45, only 15
      // minutes before it — less than the 30-minute default.
      final duration = durationForNewBlock(
        slotStart: DateTime(2026, 9, 9, 22, 45),
        existingBlocks: const [],
        settings: _settings,
      );

      expect(duration, const Duration(minutes: 15));
    });

    test('never produces an end after the day boundary, even with the '
        'overlap shrink also in play', () {
      // Same near-day-end start, but with a same-length occupied next slot
      // too — the day-end clamp and the overlap shrink should agree on 15
      // minutes rather than compounding to something shorter or invalid.
      final duration = durationForNewBlock(
        slotStart: DateTime(2026, 9, 9, 22, 45),
        existingBlocks: [
          TimeObject(
            id: '1',
            title: 'Work',
            start: DateTime(2026, 9, 9, 23),
            end: DateTime(2026, 9, 10, 1),
            kind: BlockKind.frame,
            locked: false,
          ),
        ],
        settings: _settings,
      );

      expect(duration, const Duration(minutes: 15));
      expect(
        DateTime(2026, 9, 9, 22, 45).add(duration),
        DateTime(2026, 9, 9, 23),
      );
    });
  });

  group('isValidBlockEdit', () {
    test('accepts an ordered range within the day bounds with no overlap', () {
      final valid = isValidBlockEdit(
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 9, 30),
        settings: _settings,
        day: DateTime(2026, 9, 9),
        others: const [],
      );

      expect(valid, isTrue);
    });

    test('rejects end at or before start', () {
      final valid = isValidBlockEdit(
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 9),
        settings: _settings,
        day: DateTime(2026, 9, 9),
        others: const [],
      );

      expect(valid, isFalse);
    });

    test("rejects a start before the day's own start hour", () {
      final valid = isValidBlockEdit(
        start: DateTime(2026, 9, 9, 5, 45),
        end: DateTime(2026, 9, 9, 6, 15),
        settings: _settings,
        day: DateTime(2026, 9, 9),
        others: const [],
      );

      expect(valid, isFalse);
    });

    test("rejects an end after the day's own end hour", () {
      final valid = isValidBlockEdit(
        start: DateTime(2026, 9, 9, 22, 45),
        end: DateTime(2026, 9, 9, 23, 15),
        settings: _settings,
        day: DateTime(2026, 9, 9),
        others: const [],
      );

      expect(valid, isFalse);
    });

    test('rejects a range overlapping another block', () {
      final valid = isValidBlockEdit(
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 9, 30),
        settings: _settings,
        day: DateTime(2026, 9, 9),
        others: [
          TimeObject(
            id: 'x',
            title: 'X',
            start: DateTime(2026, 9, 9, 9, 15),
            end: DateTime(2026, 9, 9, 9, 45),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
      );

      expect(valid, isFalse);
    });
  });

  group('findNextFreeSlot', () {
    const duration = Duration(minutes: 60);

    test('starts at day start when the day is empty', () {
      final slot = findNextFreeSlot(
        day: DateTime(2026, 9, 9),
        existingBlocks: const [],
        settings: _settings,
        duration: duration,
      );

      expect(slot, DateTime(2026, 9, 9, _settings.dayStartHour));
    });

    test('finds a gap between two existing blocks', () {
      final slot = findNextFreeSlot(
        day: DateTime(2026, 9, 9),
        existingBlocks: [
          TimeObject(
            id: '1',
            title: 'A',
            start: DateTime(2026, 9, 9, 6),
            end: DateTime(2026, 9, 9, 7),
            kind: BlockKind.anchor,
            locked: false,
          ),
          TimeObject(
            id: '2',
            title: 'B',
            start: DateTime(2026, 9, 9, 8),
            end: DateTime(2026, 9, 9, 9),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
        settings: _settings,
        duration: duration,
      );

      expect(slot, DateTime(2026, 9, 9, 7));
    });

    test('skips a gap shorter than duration and lands right after the last '
        'block when nothing else fits', () {
      final slot = findNextFreeSlot(
        day: DateTime(2026, 9, 9),
        existingBlocks: [
          TimeObject(
            id: '1',
            title: 'A',
            start: DateTime(2026, 9, 9, 6),
            end: DateTime(2026, 9, 9, 7),
            kind: BlockKind.anchor,
            locked: false,
          ),
          TimeObject(
            id: '2',
            title: 'B',
            // Only a 30-minute gap before this one — too short for the
            // 60-minute default duration.
            start: DateTime(2026, 9, 9, 7, 30),
            end: DateTime(2026, 9, 9, 20),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
        settings: _settings,
        duration: duration,
      );

      expect(slot, DateTime(2026, 9, 9, 20));
    });

    test('shrinks the duration to fit before the day end when nothing else '
        'fits and the last block ends too close to it', () {
      final slot = findNextFreeSlot(
        day: DateTime(2026, 9, 9),
        existingBlocks: [
          TimeObject(
            id: '1',
            title: 'A',
            start: DateTime(2026, 9, 9, 6),
            end: DateTime(2026, 9, 9, 22, 45),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
        settings: _settings,
        duration: duration,
      );

      expect(slot, DateTime(2026, 9, 9, 22, 45));
    });
  });

  group('validEditRange', () {
    final block = TimeObject(
      id: 'current',
      title: 'Current',
      start: DateTime(2026, 9, 9, 10),
      end: DateTime(2026, 9, 9, 11),
      kind: BlockKind.anchor,
      locked: false,
    );

    test('editingStart with no previous block falls back to day start', () {
      final range = validEditRange(
        block: block,
        editingStart: true,
        day: DateTime(2026, 9, 9),
        settings: _settings,
        others: const [],
      );

      expect(range.start, DateTime(2026, 9, 9, _settings.dayStartHour));
      // 15 minutes before the block's own end, per the min block duration.
      expect(range.end, DateTime(2026, 9, 9, 10, 45));
    });

    test('editingStart with a previous block starts at its end', () {
      final range = validEditRange(
        block: block,
        editingStart: true,
        day: DateTime(2026, 9, 9),
        settings: _settings,
        others: [
          TimeObject(
            id: 'prev',
            title: 'Prev',
            start: DateTime(2026, 9, 9, 8),
            end: DateTime(2026, 9, 9, 8, 30),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
      );

      expect(range.start, DateTime(2026, 9, 9, 8, 30));
    });

    test('editingStart ignores a block that is not the nearest previous '
        'one', () {
      final range = validEditRange(
        block: block,
        editingStart: true,
        day: DateTime(2026, 9, 9),
        settings: _settings,
        others: [
          TimeObject(
            id: 'far',
            title: 'Far',
            start: DateTime(2026, 9, 9, 6),
            end: DateTime(2026, 9, 9, 6, 30),
            kind: BlockKind.anchor,
            locked: false,
          ),
          TimeObject(
            id: 'near',
            title: 'Near',
            start: DateTime(2026, 9, 9, 9),
            end: DateTime(2026, 9, 9, 9, 30),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
      );

      expect(range.start, DateTime(2026, 9, 9, 9, 30));
    });

    test('editingEnd with no next block falls back to day end', () {
      final range = validEditRange(
        block: block,
        editingStart: false,
        day: DateTime(2026, 9, 9),
        settings: _settings,
        others: const [],
      );

      // 15 minutes after the block's own start, per the min block duration.
      expect(range.start, DateTime(2026, 9, 9, 10, 15));
      expect(range.end, DateTime(2026, 9, 9, _settings.dayEndHour));
    });

    test('editingEnd with a next block ends at its start', () {
      final range = validEditRange(
        block: block,
        editingStart: false,
        day: DateTime(2026, 9, 9),
        settings: _settings,
        others: [
          TimeObject(
            id: 'next',
            title: 'Next',
            start: DateTime(2026, 9, 9, 12),
            end: DateTime(2026, 9, 9, 12, 30),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
      );

      expect(range.end, DateTime(2026, 9, 9, 12));
    });
  });

  group('copyToNextDayWouldOverlap', () {
    final block = TimeObject(
      id: '1',
      title: 'Work',
      start: DateTime(2026, 9, 9, 9),
      end: DateTime(2026, 9, 9, 9, 30),
      kind: BlockKind.anchor,
      locked: false,
    );

    test('is false when the next day has no conflicting block', () {
      final overlaps = copyToNextDayWouldOverlap(
        block: block,
        nextDate: DateTime(2026, 9, 10),
        nextDayBlocks: const [],
      );

      expect(overlaps, isFalse);
    });

    test('is true when the same time slot is occupied on the next day', () {
      final overlaps = copyToNextDayWouldOverlap(
        block: block,
        nextDate: DateTime(2026, 9, 10),
        nextDayBlocks: [
          TimeObject(
            id: 'y',
            title: 'Y',
            start: DateTime(2026, 9, 10, 9, 15),
            end: DateTime(2026, 9, 10, 9, 45),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
      );

      expect(overlaps, isTrue);
    });
  });
}
