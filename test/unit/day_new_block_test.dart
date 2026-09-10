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
}
