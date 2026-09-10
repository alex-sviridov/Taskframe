import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';

void main() {
  group('dayBlocksProvider', () {
    test('loads the repository blocks for the given date', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final date = DateTime(2026, 9, 9);

      final blocks = await container.read(dayBlocksProvider(date).future);
      final expected = await InMemoryDayBlocksRepository().load(date);

      expect(blocks.map((b) => b.id), expected.map((b) => b.id));
    });

    test('addBlock appends the new block returned by the repository', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final date = DateTime(2026, 9, 9);
      await container.read(dayBlocksProvider(date).future);

      await container
          .read(dayBlocksProvider(date).notifier)
          .addBlock(
            start: DateTime(2026, 9, 9, 10),
            end: DateTime(2026, 9, 9, 10, 30),
            kind: BlockKind.anchor,
          );

      final blocks = container.read(dayBlocksProvider(date)).value!;
      expect(
        blocks.where(
          (b) =>
              b.start == DateTime(2026, 9, 9, 10) && b.kind == BlockKind.anchor,
        ),
        hasLength(1),
      );
    });

    test('addBlock returns the created block', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final date = DateTime(2026, 9, 9);
      await container.read(dayBlocksProvider(date).future);

      final created = await container
          .read(dayBlocksProvider(date).notifier)
          .addBlock(
            start: DateTime(2026, 9, 9, 10),
            end: DateTime(2026, 9, 9, 10, 30),
            kind: BlockKind.anchor,
          );

      expect(created.start, DateTime(2026, 9, 9, 10));
    });

    test('addBlock uses the given title when provided', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final date = DateTime(2026, 9, 9);
      await container.read(dayBlocksProvider(date).future);

      final created = await container
          .read(dayBlocksProvider(date).notifier)
          .addBlock(
            start: DateTime(2026, 9, 9, 10),
            end: DateTime(2026, 9, 9, 10, 30),
            kind: BlockKind.anchor,
            title: 'Gym',
          );

      expect(created.title, 'Gym');
    });

    test('updateBlock persists a valid title/time change', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final date = DateTime(2026, 9, 9);
      await container.read(dayBlocksProvider(date).future);
      final created = await container
          .read(dayBlocksProvider(date).notifier)
          .addBlock(
            start: DateTime(2026, 9, 9, 10),
            end: DateTime(2026, 9, 9, 10, 30),
            kind: BlockKind.anchor,
          );

      await container
          .read(dayBlocksProvider(date).notifier)
          .updateBlock(
            created,
            title: 'Renamed',
            start: DateTime(2026, 9, 9, 11),
            end: DateTime(2026, 9, 9, 11, 30),
          );

      final blocks = container.read(dayBlocksProvider(date)).value!;
      final updated = blocks.singleWhere((b) => b.id == created.id);
      expect(updated.title, 'Renamed');
      expect(updated.start, DateTime(2026, 9, 9, 11));
      expect(updated.end, DateTime(2026, 9, 9, 11, 30));
    });

    test('updateBlock silently no-ops on an overlapping candidate', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final date = DateTime(2026, 9, 9);
      await container.read(dayBlocksProvider(date).future);
      final notifier = container.read(dayBlocksProvider(date).notifier);
      final first = await notifier.addBlock(
        start: DateTime(2026, 9, 9, 10),
        end: DateTime(2026, 9, 9, 10, 30),
        kind: BlockKind.anchor,
      );
      await notifier.addBlock(
        start: DateTime(2026, 9, 9, 11),
        end: DateTime(2026, 9, 9, 11, 30),
        kind: BlockKind.anchor,
      );

      await notifier.updateBlock(
        first,
        start: DateTime(2026, 9, 9, 10, 45),
        end: DateTime(2026, 9, 9, 11, 15),
      );

      final blocks = container.read(dayBlocksProvider(date)).value!;
      expect(blocks.singleWhere((b) => b.id == first.id).start, first.start);
    });

    test('deleteBlock removes the block from state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final date = DateTime(2026, 9, 9);
      await container.read(dayBlocksProvider(date).future);
      final created = await container
          .read(dayBlocksProvider(date).notifier)
          .addBlock(
            start: DateTime(2026, 9, 9, 10),
            end: DateTime(2026, 9, 9, 10, 30),
            kind: BlockKind.anchor,
          );

      await container.read(dayBlocksProvider(date).notifier).deleteBlock(created);

      final blocks = container.read(dayBlocksProvider(date)).value!;
      expect(blocks.where((b) => b.id == created.id), isEmpty);
    });

    test('copyToNextDay adds a same-time copy to the following date', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Fixed, far-past dates: InMemoryDayBlocksRepository seeds hardcoded
      // blocks for whatever date happens to be "today", so a target date
      // must never risk coinciding with the real calendar date the test
      // suite runs on.
      final date = DateTime(2000, 1, 1);
      final nextDate = DateTime(2000, 1, 2);
      await container.read(dayBlocksProvider(date).future);
      final created = await container
          .read(dayBlocksProvider(date).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 10),
            end: DateTime(2000, 1, 1, 10, 30),
            kind: BlockKind.anchor,
            title: 'Gym',
          );

      await container.read(dayBlocksProvider(date).notifier).copyToNextDay(created);

      final nextDayBlocks = await container.read(dayBlocksProvider(nextDate).future);
      expect(nextDayBlocks, hasLength(1));
      expect(nextDayBlocks.single.title, 'Gym');
      expect(nextDayBlocks.single.start, DateTime(2000, 1, 2, 10));
      expect(nextDayBlocks.single.end, DateTime(2000, 1, 2, 10, 30));
    });
  });
}
