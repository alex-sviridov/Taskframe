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
  });
}
