import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';

TimeObject _block() => TimeObject(
  id: '1',
  title: 'Work',
  start: DateTime(2026, 9, 9, 9),
  end: DateTime(2026, 9, 9, 9, 30),
  kind: BlockKind.anchor,
  locked: false,
);

void main() {
  group('dragStateForDate', () {
    test('returns null when there is no drag', () {
      expect(dragStateForDate(null, DateTime(2026, 9, 9)), isNull);
    });

    test('returns the state when the date is the drag origin', () {
      final state = DragState(
        block: _block(),
        originalDate: DateTime(2026, 9, 9),
        targetDate: DateTime(2026, 9, 10),
        targetStart: DateTime(2026, 9, 10, 9),
        pointerGlobalPosition: Offset.zero,
      );

      expect(dragStateForDate(state, DateTime(2026, 9, 9)), same(state));
    });

    test('returns the state when the date is the current landzone target', () {
      final state = DragState(
        block: _block(),
        originalDate: DateTime(2026, 9, 9),
        targetDate: DateTime(2026, 9, 10),
        targetStart: DateTime(2026, 9, 10, 9),
        pointerGlobalPosition: Offset.zero,
      );

      expect(dragStateForDate(state, DateTime(2026, 9, 10)), same(state));
    });

    test(
      'returns null for a date that is neither the origin nor the target',
      () {
        final state = DragState(
          block: _block(),
          originalDate: DateTime(2026, 9, 9),
          targetDate: DateTime(2026, 9, 10),
          targetStart: DateTime(2026, 9, 10, 9),
          pointerGlobalPosition: Offset.zero,
        );

        expect(dragStateForDate(state, DateTime(2026, 9, 11)), isNull);
      },
    );
  });

  group('resizeStateForDate', () {
    test('returns null when there is no resize', () {
      expect(resizeStateForDate(null, DateTime(2026, 9, 9)), isNull);
    });

    test('returns the state when the date matches', () {
      final state = ResizeState(
        block: _block(),
        date: DateTime(2026, 9, 9),
        edge: ResizeEdge.end,
        draftStart: DateTime(2026, 9, 9, 9),
        draftEnd: DateTime(2026, 9, 9, 9, 30),
      );

      expect(resizeStateForDate(state, DateTime(2026, 9, 9)), same(state));
    });

    test('returns null for a different date', () {
      final state = ResizeState(
        block: _block(),
        date: DateTime(2026, 9, 9),
        edge: ResizeEdge.end,
        draftStart: DateTime(2026, 9, 9, 9),
        draftEnd: DateTime(2026, 9, 9, 9, 30),
      );

      expect(resizeStateForDate(state, DateTime(2026, 9, 10)), isNull);
    });
  });
}
