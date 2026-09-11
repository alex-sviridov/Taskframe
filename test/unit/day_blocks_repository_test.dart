import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
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

    test('move updates an added block\'s start, end and date', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final laterDate = date.add(const Duration(days: 1));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      final moved = await repository.move(
        added,
        fromDate: date,
        toDate: laterDate,
        newStart: DateTime(laterDate.year, laterDate.month, laterDate.day, 14),
        newEnd: DateTime(
          laterDate.year,
          laterDate.month,
          laterDate.day,
          14,
          30,
        ),
      );

      expect(moved.id, added.id);
      expect(
        moved.start,
        DateTime(laterDate.year, laterDate.month, laterDate.day, 14),
      );
      expect(
        moved.end,
        DateTime(laterDate.year, laterDate.month, laterDate.day, 14, 30),
      );
    });

    test('move removes the block from its original date', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final laterDate = date.add(const Duration(days: 1));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      await repository.move(
        added,
        fromDate: date,
        toDate: laterDate,
        newStart: DateTime(laterDate.year, laterDate.month, laterDate.day, 14),
        newEnd: DateTime(
          laterDate.year,
          laterDate.month,
          laterDate.day,
          14,
          30,
        ),
      );

      expect(await repository.load(date), isEmpty);
    });

    test('move adds the block to its new date', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final laterDate = date.add(const Duration(days: 1));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      await repository.move(
        added,
        fromDate: date,
        toDate: laterDate,
        newStart: DateTime(laterDate.year, laterDate.month, laterDate.day, 14),
        newEnd: DateTime(
          laterDate.year,
          laterDate.month,
          laterDate.day,
          14,
          30,
        ),
      );

      final blocks = await repository.load(laterDate);
      expect(blocks, hasLength(1));
      expect(blocks.single.id, added.id);
    });

    test('moving a seeded block removes it from today and adds it to the '
        'new date', () async {
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));
      final seeded = (await repository.load(today))
          .firstWhere((b) => b.id == 'breakfast');

      await repository.move(
        seeded,
        fromDate: today,
        toDate: tomorrow,
        newStart: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8),
        newEnd: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8, 30),
      );

      final todayBlocks = await repository.load(today);
      expect(todayBlocks.where((b) => b.id == 'breakfast'), isEmpty);

      final tomorrowBlocks = await repository.load(tomorrow);
      expect(tomorrowBlocks.single.id, 'breakfast');
      expect(
        tomorrowBlocks.single.start,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8),
      );
    });

    test('move within the same date just updates the block\'s time', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      await repository.move(
        added,
        fromDate: date,
        toDate: date,
        newStart: DateTime(date.year, date.month, date.day, 15),
        newEnd: DateTime(date.year, date.month, date.day, 15, 30),
      );

      final blocks = await repository.load(date);
      expect(blocks, hasLength(1));
      expect(
        blocks.single.start,
        DateTime(date.year, date.month, date.day, 15),
      );
    });

    test('add defaults categoryId to the default category', () async {
      final date = DateTime.now().add(const Duration(days: 3));

      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      expect(added.categoryId, Category.defaultId);
    });

    test('add uses the given categoryId when provided', () async {
      final date = DateTime.now().add(const Duration(days: 3));

      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
        categoryId: 'category-1',
      );

      expect(added.categoryId, 'category-1');
    });

    test('move preserves the block\'s categoryId', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final laterDate = date.add(const Duration(days: 1));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
        categoryId: 'category-1',
      );

      final moved = await repository.move(
        added,
        fromDate: date,
        toDate: laterDate,
        newStart: DateTime(laterDate.year, laterDate.month, laterDate.day, 14),
        newEnd: DateTime(
          laterDate.year,
          laterDate.month,
          laterDate.day,
          14,
          30,
        ),
      );

      expect(moved.categoryId, 'category-1');
    });

    test('update changes an added block\'s categoryId', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      final updated = await repository.update(
        added,
        date: date,
        categoryId: 'category-1',
      );

      expect(updated.categoryId, 'category-1');
    });

    test('update leaves categoryId unchanged when not given', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
        categoryId: 'category-1',
      );

      final updated = await repository.update(
        added,
        date: date,
        title: 'Renamed',
      );

      expect(updated.categoryId, 'category-1');
    });

    test('add uses the given title when provided', () async {
      final date = DateTime.now().add(const Duration(days: 3));

      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
        title: 'Gym',
      );

      expect(added.title, 'Gym');
    });

    test('update changes an added block\'s title, start and end', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      final updated = await repository.update(
        added,
        date: date,
        title: 'Renamed',
        start: DateTime(date.year, date.month, date.day, 11),
        end: DateTime(date.year, date.month, date.day, 11, 30),
      );

      expect(updated.id, added.id);
      expect(updated.title, 'Renamed');
      expect(updated.start, DateTime(date.year, date.month, date.day, 11));
      expect(updated.end, DateTime(date.year, date.month, date.day, 11, 30));
    });

    test('update changes an added block\'s kind', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      final updated = await repository.update(
        added,
        date: date,
        kind: BlockKind.frame,
      );

      expect(updated.kind, BlockKind.frame);
    });

    test('update leaves fields unspecified as null unchanged', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      final updated = await repository.update(
        added,
        date: date,
        title: 'Renamed',
      );

      expect(updated.start, added.start);
      expect(updated.end, added.end);
    });

    test('update replaces the block in a later load for that date', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      await repository.update(added, date: date, title: 'Renamed');

      final blocks = await repository.load(date);
      expect(blocks, hasLength(1));
      expect(blocks.single.title, 'Renamed');
    });

    test('updating a seeded block promotes it and keeps its new title on '
        'later loads', () async {
      final today = DateTime.now();
      final seeded = (await repository.load(today))
          .firstWhere((b) => b.id == 'breakfast');

      await repository.update(seeded, date: today, title: 'Brunch');

      final blocks = await repository.load(today);
      expect(blocks.where((b) => b.id == 'breakfast'), hasLength(1));
      expect(blocks.firstWhere((b) => b.id == 'breakfast').title, 'Brunch');
    });

    test('delete removes an added block from a later load', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      await repository.delete(added, date: date);

      expect(await repository.load(date), isEmpty);
    });

    test('delete removes a seeded block from a later load', () async {
      final today = DateTime.now();
      final seeded = (await repository.load(today))
          .firstWhere((b) => b.id == 'breakfast');

      await repository.delete(seeded, date: today);

      final blocks = await repository.load(today);
      expect(blocks.where((b) => b.id == 'breakfast'), isEmpty);
    });
  });
}
