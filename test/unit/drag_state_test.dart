import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';

TimeObject _block() => TimeObject(
  id: '1',
  title: 'Work',
  start: DateTime(2026, 9, 9, 9),
  end: DateTime(2026, 9, 9, 9, 30),
  kind: BlockKind.anchor,
  locked: false,
);

void main() {
  group('DragState', () {
    test('copyWith overrides only the given fields', () {
      final state = DragState(
        block: _block(),
        originalColumn: DayColumn(DateTime(2026, 9, 9)),
        targetColumn: DayColumn(DateTime(2026, 9, 9)),
        targetStart: DateTime(2026, 9, 9, 9),
        pointerGlobalPosition: const Offset(10, 20),
      );

      final updated = state.copyWith(
        targetColumn: DayColumn(DateTime(2026, 9, 10)),
        targetStart: DateTime(2026, 9, 10, 11),
        pointerGlobalPosition: const Offset(30, 40),
      );

      expect(updated.block, state.block);
      expect(updated.originalColumn, state.originalColumn);
      expect(updated.targetColumn, DayColumn(DateTime(2026, 9, 10)));
      expect(updated.targetStart, DateTime(2026, 9, 10, 11));
      expect(updated.pointerGlobalPosition, const Offset(30, 40));
    });

    test('copyWith with no arguments returns identical values', () {
      final state = DragState(
        block: _block(),
        originalColumn: DayColumn(DateTime(2026, 9, 9)),
        targetColumn: DayColumn(DateTime(2026, 9, 9)),
        targetStart: DateTime(2026, 9, 9, 9),
        pointerGlobalPosition: const Offset(10, 20),
      );

      final copy = state.copyWith();

      expect(copy.targetColumn, state.targetColumn);
      expect(copy.targetStart, state.targetStart);
      expect(copy.pointerGlobalPosition, state.pointerGlobalPosition);
    });

    test('copyWith(clearTarget: true) drops the landzone entirely', () {
      final state = DragState(
        block: _block(),
        originalColumn: DayColumn(DateTime(2026, 9, 9)),
        targetColumn: DayColumn(DateTime(2026, 9, 9)),
        targetStart: DateTime(2026, 9, 9, 9),
        pointerGlobalPosition: const Offset(10, 20),
      );
      expect(state.hasTarget, isTrue);

      final cleared = state.copyWith(
        clearTarget: true,
        pointerGlobalPosition: const Offset(30, 40),
      );

      expect(cleared.targetColumn, isNull);
      expect(cleared.targetStart, isNull);
      expect(cleared.hasTarget, isFalse);
      expect(cleared.block, state.block);
      expect(cleared.originalColumn, state.originalColumn);
      expect(cleared.pointerGlobalPosition, const Offset(30, 40));
    });
  });
}
