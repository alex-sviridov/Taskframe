import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
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
  group('ResizeState', () {
    test('copyWith overrides only the given fields', () {
      final state = ResizeState(
        block: _block(),
        date: DateTime(2026, 9, 9),
        edge: ResizeEdge.end,
        draftStart: DateTime(2026, 9, 9, 9),
        draftEnd: DateTime(2026, 9, 9, 9, 30),
      );

      final updated = state.copyWith(draftEnd: DateTime(2026, 9, 9, 10));

      expect(updated.block, state.block);
      expect(updated.date, state.date);
      expect(updated.edge, state.edge);
      expect(updated.draftStart, state.draftStart);
      expect(updated.draftEnd, DateTime(2026, 9, 9, 10));
    });

    test('copyWith with no arguments returns identical values', () {
      final state = ResizeState(
        block: _block(),
        date: DateTime(2026, 9, 9),
        edge: ResizeEdge.start,
        draftStart: DateTime(2026, 9, 9, 9),
        draftEnd: DateTime(2026, 9, 9, 9, 30),
      );

      final copy = state.copyWith();

      expect(copy.draftStart, state.draftStart);
      expect(copy.draftEnd, state.draftEnd);
    });
  });
}
