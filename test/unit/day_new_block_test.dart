import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';

const _settings = DaySettings(dayStartHour: 6, dayEndHour: 23);
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

  group('durationForNewBlock', () {
    test('defaults to 30 minutes when both slots are free', () {
      final duration = durationForNewBlock(
        slotStart: DateTime(2026, 9, 9, 9),
        existingBlocks: const [],
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
      );

      expect(duration, const Duration(minutes: 15));
    });
  });
}
