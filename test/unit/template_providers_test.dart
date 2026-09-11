import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/template/providers.dart';

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  group('templateListProvider', () {
    test('starts empty', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(templateListProvider.future), isEmpty);
    });

    test('addTemplate appends a new template and returns it', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(templateListProvider.future);

      final added = await container
          .read(templateListProvider.notifier)
          .addTemplate(name: 'Weekday');

      expect(added.name, 'Weekday');
      expect(container.read(templateListProvider).value, [added]);
    });

    test('renameTemplate persists the new name', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(templateListProvider.future);
      final added = await container
          .read(templateListProvider.notifier)
          .addTemplate(name: 'Weekday');

      await container.read(templateListProvider.notifier).renameTemplate(added, name: 'Renamed');

      expect(container.read(templateListProvider).value!.single.name, 'Renamed');
    });

    test('deleteTemplate removes the template', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(templateListProvider.future);
      final added = await container
          .read(templateListProvider.notifier)
          .addTemplate(name: 'Weekday');

      await container.read(templateListProvider.notifier).deleteTemplate(added);

      expect(container.read(templateListProvider).value, isEmpty);
    });

    test(
      'deleteTemplate also clears that template\'s blocks, so a later '
      'template reusing the id cannot inherit them',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(templateListProvider.future);
        final added = await container
            .read(templateListProvider.notifier)
            .addTemplate(name: 'Weekday');
        await container.read(templateBlocksProvider(added.id).future);
        await container
            .read(templateBlocksProvider(added.id).notifier)
            .addBlock(
              start: DateTime(2000, 1, 1, 9),
              end: DateTime(2000, 1, 1, 9, 30),
              kind: BlockKind.anchor,
            );

        await container
            .read(templateListProvider.notifier)
            .deleteTemplate(added);

        expect(
          await container.read(templateBlocksProvider(added.id).future),
          isEmpty,
        );
      },
    );
  });

  group('templateBlocksProvider', () {
    test('addBlock appends the new block returned by the repository', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(templateBlocksProvider('t1').future);

      await container
          .read(templateBlocksProvider('t1').notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 10),
            end: DateTime(2000, 1, 1, 10, 30),
            kind: BlockKind.anchor,
          );

      final blocks = container.read(templateBlocksProvider('t1')).value!;
      expect(blocks, hasLength(1));
    });

    test('updateBlock silently no-ops on an overlapping candidate', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(templateBlocksProvider('t1').future);
      final notifier = container.read(templateBlocksProvider('t1').notifier);
      final first = await notifier.addBlock(
        start: DateTime(2000, 1, 1, 10),
        end: DateTime(2000, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );
      await notifier.addBlock(
        start: DateTime(2000, 1, 1, 11),
        end: DateTime(2000, 1, 1, 11, 30),
        kind: BlockKind.anchor,
      );

      await notifier.updateBlock(
        first,
        start: DateTime(2000, 1, 1, 10, 45),
        end: DateTime(2000, 1, 1, 11, 15),
      );

      final blocks = container.read(templateBlocksProvider('t1')).value!;
      expect(blocks.singleWhere((b) => b.id == first.id).start, first.start);
    });

    test('deleteBlock removes the block from state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(templateBlocksProvider('t1').future);
      final created = await container
          .read(templateBlocksProvider('t1').notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 10),
            end: DateTime(2000, 1, 1, 10, 30),
            kind: BlockKind.anchor,
          );

      await container.read(templateBlocksProvider('t1').notifier).deleteBlock(created);

      expect(container.read(templateBlocksProvider('t1')).value, isEmpty);
    });
  });

  group('TemplateScheduleController', () {
    test('blocksOf reads templateBlocksProvider for the column\'s templateId', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProvider);
      const controller = TemplateScheduleController();
      await container.read(templateBlocksProvider('t1').future);

      expect(controller.blocksOf(ref, const TemplateColumn('t1')), isEmpty);
    });

    test('moveBlock moves a block between two templateIds', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProvider);
      const controller = TemplateScheduleController();
      await container.read(templateBlocksProvider('t1').future);
      final added = await container
          .read(templateBlocksProvider('t1').notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 9),
            end: DateTime(2000, 1, 1, 9, 30),
            kind: BlockKind.anchor,
          );

      await controller.moveBlock(
        ref,
        block: added,
        fromColumn: const TemplateColumn('t1'),
        toColumn: const TemplateColumn('t2'),
        newStart: DateTime(2000, 1, 1, 14),
        newEnd: DateTime(2000, 1, 1, 14, 30),
      );

      expect(container.read(templateBlocksProvider('t1')).value, isEmpty);
      expect(container.read(templateBlocksProvider('t2')).value!.single.id, added.id);
    });

    test(
      'rejects a non-template column rather than silently mishandling it '
      '(the invariant the drag resolver\'s variant scoping upholds)',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final ref = container.read(_refProvider);
        const controller = TemplateScheduleController();
        final day = DayColumn(DateTime(2026, 9, 9));

        expect(
          () => controller.blocksOf(ref, day),
          throwsA(isA<TypeError>()),
        );
        expect(
          () => controller.moveBlock(
            ref,
            block: TimeObject(
              id: 'b1',
              title: 'Block',
              start: DateTime(2000, 1, 1, 9),
              end: DateTime(2000, 1, 1, 9, 30),
              kind: BlockKind.anchor,
              locked: false,
            ),
            fromColumn: day,
            toColumn: day,
            newStart: DateTime(2000, 1, 1, 10),
            newEnd: DateTime(2000, 1, 1, 10, 30),
          ),
          throwsA(isA<TypeError>()),
        );
      },
    );
  });
}
