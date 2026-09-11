import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/template/providers.dart';

void main() {
  group('DayBlocksNotifier.applyTemplate', () {
    test('adds every non-overlapping template block to the day', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final date = DateTime(2026, 9, 20);
      await container.read(dayBlocksProvider(date).future);

      final template = await container
          .read(templateListProvider.notifier)
          .addTemplate(name: 'Morning');
      await container
          .read(templateBlocksProvider(template.id).notifier)
          .addBlock(
            start: DateTime(
              templateAnchorDate.year,
              templateAnchorDate.month,
              templateAnchorDate.day,
              8,
            ),
            end: DateTime(
              templateAnchorDate.year,
              templateAnchorDate.month,
              templateAnchorDate.day,
              9,
            ),
            kind: BlockKind.anchor,
            title: 'Breakfast',
          );

      final result = await container
          .read(dayBlocksProvider(date).notifier)
          .applyTemplate(template.id);

      expect(result.skipped, isEmpty);
      expect(result.addedIds, hasLength(1));

      final dayBlocks = container.read(dayBlocksProvider(date)).value!;
      expect(dayBlocks.map((b) => b.title), contains('Breakfast'));
      expect(dayBlocks.single.id, result.addedIds.single);
      expect(dayBlocks.single.start, DateTime(2026, 9, 20, 8));
    });

    test('skips a template block overlapping an existing day block', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final date = DateTime(2026, 9, 21);
      await container.read(dayBlocksProvider(date).future);
      await container
          .read(dayBlocksProvider(date).notifier)
          .addBlock(
            start: DateTime(2026, 9, 21, 8, 30),
            end: DateTime(2026, 9, 21, 9, 30),
            kind: BlockKind.anchor,
            title: 'Existing',
          );

      final template = await container
          .read(templateListProvider.notifier)
          .addTemplate(name: 'Morning');
      await container
          .read(templateBlocksProvider(template.id).notifier)
          .addBlock(
            start: DateTime(
              templateAnchorDate.year,
              templateAnchorDate.month,
              templateAnchorDate.day,
              8,
            ),
            end: DateTime(
              templateAnchorDate.year,
              templateAnchorDate.month,
              templateAnchorDate.day,
              9,
            ),
            kind: BlockKind.anchor,
            title: 'Breakfast',
          );

      final result = await container
          .read(dayBlocksProvider(date).notifier)
          .applyTemplate(template.id);

      expect(result.addedIds, isEmpty);
      expect(result.skipped, [
        (start: DateTime(2026, 9, 21, 8), end: DateTime(2026, 9, 21, 9)),
      ]);
      final dayBlocks = container.read(dayBlocksProvider(date)).value!;
      expect(dayBlocks.map((b) => b.title), ['Existing']);
    });
  });
}
