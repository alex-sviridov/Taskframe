import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/now/now_selection.dart';

TimeObject _block(
  String id,
  int startHour,
  int startMinute,
  int endHour,
  int endMinute, {
  BlockKind kind = BlockKind.anchor,
  String categoryId = '0',
}) => TimeObject(
  id: id,
  title: id,
  start: DateTime(2026, 9, 19, startHour, startMinute),
  end: DateTime(2026, 9, 19, endHour, endMinute),
  kind: kind,
  locked: false,
  categoryId: categoryId,
);

void main() {
  group('selectNowEvents', () {
    test('picks the block covering now as current, with previous/next', () {
      final blocks = [
        _block('a', 8, 0, 9, 0),
        _block('b', 9, 0, 10, 0),
        _block('c', 10, 0, 11, 0),
        _block('d', 11, 0, 12, 0),
      ];
      final now = DateTime(2026, 9, 19, 9, 30);

      final result = selectNowEvents(blocks, now);

      expect(result.previous!.id, 'a');
      expect(result.current!.id, 'b');
      expect(result.next1!.id, 'c');
      expect(result.next2!.id, 'd');
    });

    test(
      'borrows the nearest upcoming block as current when now is in a gap',
      () {
        final blocks = [_block('a', 8, 0, 9, 0), _block('b', 10, 0, 11, 0)];
        final now = DateTime(2026, 9, 19, 9, 30);

        final result = selectNowEvents(blocks, now);

        expect(result.current!.id, 'b');
        expect(result.previous!.id, 'a');
        expect(result.next1, isNull);
        expect(result.next2, isNull);
      },
    );

    test(
      'when overlapping blocks both cover now, the latest-starting one wins',
      () {
        final frame = _block('frame', 8, 0, 12, 0, kind: BlockKind.frame);
        final anchor = _block('anchor', 9, 0, 9, 30);
        final now = DateTime(2026, 9, 19, 9, 15);

        final result = selectNowEvents([frame, anchor], now);

        expect(result.current!.id, 'anchor');
      },
    );

    test('when the day is over, only previous is filled', () {
      final blocks = [_block('a', 8, 0, 9, 0), _block('b', 9, 0, 10, 0)];
      final now = DateTime(2026, 9, 19, 23);

      final result = selectNowEvents(blocks, now);

      expect(result.previous!.id, 'b');
      expect(result.current, isNull);
      expect(result.next1, isNull);
      expect(result.next2, isNull);
    });

    test('every slot is null when there are no blocks at all', () {
      final result = selectNowEvents([], DateTime(2026, 9, 19, 9));

      expect(result.previous, isNull);
      expect(result.current, isNull);
      expect(result.next1, isNull);
      expect(result.next2, isNull);
    });

    test('before the first block of the day, borrows it as current with no '
        'previous', () {
      final blocks = [
        _block('a', 9, 0, 10, 0),
        _block('b', 11, 0, 12, 0),
        _block('c', 13, 0, 14, 0),
      ];
      final now = DateTime(2026, 9, 19, 8);

      final result = selectNowEvents(blocks, now);

      expect(result.previous, isNull);
      expect(result.current!.id, 'a');
      expect(result.next1!.id, 'b');
      expect(result.next2!.id, 'c');
    });
  });
}
