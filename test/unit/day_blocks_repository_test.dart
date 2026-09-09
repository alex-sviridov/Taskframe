import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/models/time_object.dart';

void main() {
  group('InMemoryDayBlocksRepository', () {
    late InMemoryDayBlocksRepository repository;

    setUp(() => repository = InMemoryDayBlocksRepository());

    test('load returns a hardcoded, non-empty list for today', () async {
      final blocks = await repository.load(DateTime.now());

      expect(blocks, isNotEmpty);
    });

    test('load returns an empty list for a date other than today', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      final blocks = await repository.load(yesterday);

      expect(blocks, isEmpty);
    });

    test('every seeded block starts and ends on the requested date', () async {
      final today = DateTime.now();

      final blocks = await repository.load(today);

      for (final block in blocks) {
        expect(block.start.year, today.year);
        expect(block.start.month, today.month);
        expect(block.start.day, today.day);
      }
    });

    test('add returns a block with the given start, end and kind', () async {
      final date = DateTime.now().add(const Duration(days: 3));

      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      expect(added.start, DateTime(date.year, date.month, date.day, 10));
      expect(added.end, DateTime(date.year, date.month, date.day, 10, 30));
      expect(added.kind, BlockKind.anchor);
      expect(added.title, 'title');
      expect(added.locked, isFalse);
    });

    test(
      'a block added for a date shows up in a later load for that date',
      () async {
        final date = DateTime.now().add(const Duration(days: 3));

        await repository.add(
          date,
          start: DateTime(date.year, date.month, date.day, 10),
          end: DateTime(date.year, date.month, date.day, 10, 30),
          kind: BlockKind.frame,
        );
        final blocks = await repository.load(date);

        expect(blocks, hasLength(1));
        expect(blocks.single.kind, BlockKind.frame);
      },
    );

    test('two added blocks get distinct ids', () async {
      final date = DateTime.now().add(const Duration(days: 3));

      final first = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );
      final second = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 11),
        end: DateTime(date.year, date.month, date.day, 11, 30),
        kind: BlockKind.anchor,
      );

      expect(first.id, isNot(equals(second.id)));
    });
  });
}
