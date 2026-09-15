import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/draft_state.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
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
  group('dragStateForColumn', () {
    test('returns null when there is no drag', () {
      expect(dragStateForColumn(null, DayColumn(DateTime(2026, 9, 9))), isNull);
    });

    test('returns the state when the column is the drag origin', () {
      final state = DragState(
        block: _block(),
        originalColumn: DayColumn(DateTime(2026, 9, 9)),
        targetColumn: DayColumn(DateTime(2026, 9, 10)),
        targetStart: DateTime(2026, 9, 10, 9),
        pointerGlobalPosition: Offset.zero,
      );

      expect(
        dragStateForColumn(state, DayColumn(DateTime(2026, 9, 9))),
        same(state),
      );
    });

    test(
      'returns the state when the column is the current landzone target',
      () {
        final state = DragState(
          block: _block(),
          originalColumn: DayColumn(DateTime(2026, 9, 9)),
          targetColumn: DayColumn(DateTime(2026, 9, 10)),
          targetStart: DateTime(2026, 9, 10, 9),
          pointerGlobalPosition: Offset.zero,
        );

        expect(
          dragStateForColumn(state, DayColumn(DateTime(2026, 9, 10))),
          same(state),
        );
      },
    );

    test(
      'returns null for a column that is neither the origin nor the target',
      () {
        final state = DragState(
          block: _block(),
          originalColumn: DayColumn(DateTime(2026, 9, 9)),
          targetColumn: DayColumn(DateTime(2026, 9, 10)),
          targetStart: DateTime(2026, 9, 10, 9),
          pointerGlobalPosition: Offset.zero,
        );

        expect(
          dragStateForColumn(state, DayColumn(DateTime(2026, 9, 11))),
          isNull,
        );
      },
    );
  });

  group('resizeStateForColumn', () {
    test('returns null when there is no resize', () {
      expect(
        resizeStateForColumn(null, DayColumn(DateTime(2026, 9, 9))),
        isNull,
      );
    });

    test('returns the state when the column matches', () {
      final state = ResizeState(
        block: _block(),
        column: DayColumn(DateTime(2026, 9, 9)),
        edge: ResizeEdge.end,
        draftStart: DateTime(2026, 9, 9, 9),
        draftEnd: DateTime(2026, 9, 9, 9, 30),
      );

      expect(
        resizeStateForColumn(state, DayColumn(DateTime(2026, 9, 9))),
        same(state),
      );
    });

    test('returns null for a different column', () {
      final state = ResizeState(
        block: _block(),
        column: DayColumn(DateTime(2026, 9, 9)),
        edge: ResizeEdge.end,
        draftStart: DateTime(2026, 9, 9, 9),
        draftEnd: DateTime(2026, 9, 9, 9, 30),
      );

      expect(
        resizeStateForColumn(state, DayColumn(DateTime(2026, 9, 10))),
        isNull,
      );
    });
  });

  group('draftStateForColumn', () {
    test('returns null when there is no draft', () {
      expect(
        draftStateForColumn(null, DayColumn(DateTime(2026, 9, 9))),
        isNull,
      );
    });

    test('returns the state when the column matches', () {
      final state = DraftState(
        column: DayColumn(DateTime(2026, 9, 9)),
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 9, 30),
      );

      expect(
        draftStateForColumn(state, DayColumn(DateTime(2026, 9, 9))),
        same(state),
      );
    });

    test('returns null for a different column', () {
      final state = DraftState(
        column: DayColumn(DateTime(2026, 9, 9)),
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 9, 30),
      );

      expect(
        draftStateForColumn(state, DayColumn(DateTime(2026, 9, 10))),
        isNull,
      );
    });
  });
}
