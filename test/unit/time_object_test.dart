import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
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

    test('categoryId defaults to the default category when not given', () {
      final block = TimeObject(
        id: '1',
        title: 'Work',
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 10),
        kind: BlockKind.frame,
        locked: false,
      );

      expect(block.categoryId, Category.defaultId);
    });

    test('categoryId can be set explicitly', () {
      final block = TimeObject(
        id: '1',
        title: 'Work',
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 10),
        kind: BlockKind.frame,
        locked: false,
        categoryId: 'category-1',
      );

      expect(block.categoryId, 'category-1');
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

  group('TimeObject.overlaps', () {
    TimeObject block({required int startHour, required int endHour}) =>
        TimeObject(
          id: '1',
          title: 'Work',
          start: DateTime(2026, 9, 9, startHour),
          end: DateTime(2026, 9, 9, endHour),
          kind: BlockKind.frame,
          locked: false,
        );

    test('is true when the given range overlaps the block', () {
      final b = block(startHour: 9, endHour: 10);
      expect(
        b.overlaps(DateTime(2026, 9, 9, 9, 30), DateTime(2026, 9, 9, 11)),
        isTrue,
      );
    });

    test('is false when the given range ends exactly at the block start', () {
      final b = block(startHour: 9, endHour: 10);
      expect(
        b.overlaps(DateTime(2026, 9, 9, 8), DateTime(2026, 9, 9, 9)),
        isFalse,
      );
    });

    test('is false when the given range starts exactly at the block end', () {
      final b = block(startHour: 9, endHour: 10);
      expect(
        b.overlaps(DateTime(2026, 9, 9, 10), DateTime(2026, 9, 9, 11)),
        isFalse,
      );
    });

    test('is false when the given range is entirely outside the block', () {
      final b = block(startHour: 9, endHour: 10);
      expect(
        b.overlaps(DateTime(2026, 9, 9, 11), DateTime(2026, 9, 9, 12)),
        isFalse,
      );
    });
  });
}
