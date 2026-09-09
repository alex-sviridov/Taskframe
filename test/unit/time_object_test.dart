import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/time_object.dart';

void main() {
  group('TimeObject', () {
    test('constructs when start and end are on the 15-minute grid', () {
      final block = TimeObject(
        id: '1',
        title: 'Work',
        start: DateTime(2026, 9, 9, 9, 15),
        end: DateTime(2026, 9, 9, 13, 30),
        kind: BlockKind.frame,
        locked: false,
      );

      expect(block.title, 'Work');
      expect(block.kind, BlockKind.frame);
    });

    test('throws when start is off the 15-minute grid', () {
      expect(
        () => TimeObject(
          id: '1',
          title: 'Work',
          start: DateTime(2026, 9, 9, 9, 5),
          end: DateTime(2026, 9, 9, 13, 30),
          kind: BlockKind.frame,
          locked: false,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws when end is off the 15-minute grid', () {
      expect(
        () => TimeObject(
          id: '1',
          title: 'Work',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 13, 33),
          kind: BlockKind.frame,
          locked: false,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws when end is not after start', () {
      expect(
        () => TimeObject(
          id: '1',
          title: 'Work',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 9),
          kind: BlockKind.frame,
          locked: false,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
