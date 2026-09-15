import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/day/data/sembast_day_blocks_repository.dart';
import 'package:taskframe/features/day/models/time_object.dart';

void main() {
  group('SembastDayBlocksRepository', () {
    late SembastDayBlocksRepository repository;
    late Database db;

    setUp(() async {
      db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastDayBlocksRepository(db);
    });

    test('load returns an empty list when nothing has been added', () async {
      expect(await repository.load(DateTime(2030)), isEmpty);
    });

    test('add returns a block with the given start, end and kind', () async {
      final added = await repository.add(
        DateTime(2030),
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      expect(added.start, DateTime(2030, 1, 1, 10));
      expect(added.end, DateTime(2030, 1, 1, 10, 30));
      expect(added.kind, BlockKind.anchor);
      expect(added.title, '');
    });

    test('add defaults categoryId to the default category', () async {
      final added = await repository.add(
        DateTime(2030),
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      expect(added.categoryId, '0');
    });

    test(
      'a block added for a date shows up in a later load for that date',
      () async {
        final date = DateTime(2030);
        await repository.add(
          date,
          start: DateTime(2030, 1, 1, 10),
          end: DateTime(2030, 1, 1, 10, 30),
          kind: BlockKind.frame,
        );

        final blocks = await repository.load(date);

        expect(blocks, hasLength(1));
        expect(blocks.single.kind, BlockKind.frame);
      },
    );

    test('a block added for one date is invisible on another', () async {
      await repository.add(
        DateTime(2030),
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      expect(await repository.load(DateTime(2030, 1, 2)), isEmpty);
    });

    test('two added blocks get distinct ids', () async {
      final date = DateTime(2030);
      final first = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );
      final second = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 11),
        end: DateTime(2030, 1, 1, 11, 30),
        kind: BlockKind.anchor,
      );

      expect(first.id, isNot(second.id));
    });

    test(
      'move updates start/end/date and is queryable on the new date',
      () async {
        final date = DateTime(2030);
        final laterDate = DateTime(2030, 1, 2);
        final added = await repository.add(
          date,
          start: DateTime(2030, 1, 1, 10),
          end: DateTime(2030, 1, 1, 10, 30),
          kind: BlockKind.anchor,
        );

        final moved = await repository.move(
          added,
          fromDate: date,
          toDate: laterDate,
          newStart: DateTime(2030, 1, 2, 14),
          newEnd: DateTime(2030, 1, 2, 14, 30),
        );

        expect(moved.id, added.id);
        expect(await repository.load(date), isEmpty);
        final blocks = await repository.load(laterDate);
        expect(blocks, hasLength(1));
        expect(blocks.single.start, DateTime(2030, 1, 2, 14));
      },
    );

    test('update changes title/start/end/kind, replacing the block in a '
        'later load', () async {
      final date = DateTime(2030);
      final added = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      final updated = await repository.update(
        added,
        date: date,
        title: 'Renamed',
        start: DateTime(2030, 1, 1, 11),
        end: DateTime(2030, 1, 1, 11, 30),
        kind: BlockKind.frame,
      );

      expect(updated.id, added.id);
      expect(updated.title, 'Renamed');
      expect(updated.kind, BlockKind.frame);
      final blocks = await repository.load(date);
      expect(blocks, hasLength(1));
      expect(blocks.single.title, 'Renamed');
    });

    test('update leaves categoryId unchanged when not given', () async {
      final date = DateTime(2030);
      final added = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
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

    test('delete removes the block from a later load', () async {
      final date = DateTime(2030);
      final added = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      await repository.delete(added, date: date);

      expect(await repository.load(date), isEmpty);
    });

    test('delete soft-deletes: block stays in the store but excluded from '
        'load', () async {
      final today = DateTime.now();
      final added = await repository.add(
        today,
        start: DateTime(today.year, today.month, today.day, 9),
        end: DateTime(today.year, today.month, today.day, 10),
        kind: BlockKind.frame,
      );

      await repository.delete(added, date: today);

      expect(await repository.load(today), isEmpty);
      final record = await dayBlocksStore.record(added.id).get(db);
      expect(record!['deleted'], isTrue);
    });
  });
}
