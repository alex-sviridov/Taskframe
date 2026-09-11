import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_schedule_controller.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';

// Fixed, far-past date: InMemoryDayBlocksRepository seeds hardcoded blocks
// for whatever date happens to be the real wall-clock "today", so tests must
// never risk a date coinciding with it.
final _date = DateTime(2000, 1, 1);

void main() {
  group('resizeStateProvider', () {
    test('starts null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(resizeStateProvider), isNull);
    });

    test('start sets block, date, edge and initial draft to the block\'s '
        'own start/end', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(dayBlocksProvider(_date).future);
      await container
          .read(dayBlocksProvider(_date).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 9),
            end: DateTime(2000, 1, 1, 9, 30),
            kind: BlockKind.anchor,
          );
      final block = container.read(dayBlocksProvider(_date)).value!.last;

      container
          .read(resizeStateProvider.notifier)
          .start(
            block: block,
            column: DayColumn(_date),
            controller: const DayScheduleController(),
            edge: ResizeEdge.end,
          );

      final state = container.read(resizeStateProvider)!;
      expect(state.block, block);
      expect(state.column, DayColumn(_date));
      expect(state.edge, ResizeEdge.end);
      expect(state.draftStart, block.start);
      expect(state.draftEnd, block.end);
    });

    test('update on the end edge moves draftEnd and leaves draftStart', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(resizeStateProvider.notifier)
          .start(
            block: TimeObject(
              id: '1',
              title: 'Work',
              start: DateTime(2000, 1, 1, 9),
              end: DateTime(2000, 1, 1, 9, 30),
              kind: BlockKind.anchor,
              locked: false,
            ),
            column: DayColumn(_date),
            controller: const DayScheduleController(),
            edge: ResizeEdge.end,
          );

      container
          .read(resizeStateProvider.notifier)
          .update(DateTime(2000, 1, 1, 10));

      final state = container.read(resizeStateProvider)!;
      expect(state.draftStart, DateTime(2000, 1, 1, 9));
      expect(state.draftEnd, DateTime(2000, 1, 1, 10));
    });

    test('update on the start edge moves draftStart and leaves draftEnd', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(resizeStateProvider.notifier)
          .start(
            block: TimeObject(
              id: '1',
              title: 'Work',
              start: DateTime(2000, 1, 1, 9),
              end: DateTime(2000, 1, 1, 9, 30),
              kind: BlockKind.anchor,
              locked: false,
            ),
            column: DayColumn(_date),
            controller: const DayScheduleController(),
            edge: ResizeEdge.start,
          );

      container
          .read(resizeStateProvider.notifier)
          .update(DateTime(2000, 1, 1, 8));

      final state = container.read(resizeStateProvider)!;
      expect(state.draftStart, DateTime(2000, 1, 1, 8));
      expect(state.draftEnd, DateTime(2000, 1, 1, 9, 30));
    });

    test('update on the end edge clamps to a minimum 15-minute duration', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(resizeStateProvider.notifier)
          .start(
            block: TimeObject(
              id: '1',
              title: 'Work',
              start: DateTime(2000, 1, 1, 9),
              end: DateTime(2000, 1, 1, 9, 30),
              kind: BlockKind.anchor,
              locked: false,
            ),
            column: DayColumn(_date),
            controller: const DayScheduleController(),
            edge: ResizeEdge.end,
          );

      container
          .read(resizeStateProvider.notifier)
          .update(DateTime(2000, 1, 1, 9));

      final state = container.read(resizeStateProvider)!;
      expect(state.draftEnd, DateTime(2000, 1, 1, 9, 15));
    });

    test('update on the start edge clamps to a minimum 15-minute duration', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(resizeStateProvider.notifier)
          .start(
            block: TimeObject(
              id: '1',
              title: 'Work',
              start: DateTime(2000, 1, 1, 9),
              end: DateTime(2000, 1, 1, 9, 30),
              kind: BlockKind.anchor,
              locked: false,
            ),
            column: DayColumn(_date),
            controller: const DayScheduleController(),
            edge: ResizeEdge.start,
          );

      container
          .read(resizeStateProvider.notifier)
          .update(DateTime(2000, 1, 1, 9, 30));

      final state = container.read(resizeStateProvider)!;
      expect(state.draftStart, DateTime(2000, 1, 1, 9, 15));
    });

    test('update on the end edge clamps to the start of the next block instead '
        'of overlapping it', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(dayBlocksProvider(_date).future);
      await container
          .read(dayBlocksProvider(_date).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 10),
            end: DateTime(2000, 1, 1, 10, 30),
            kind: BlockKind.anchor,
          );
      container
          .read(resizeStateProvider.notifier)
          .start(
            block: TimeObject(
              id: '1',
              title: 'Work',
              start: DateTime(2000, 1, 1, 9),
              end: DateTime(2000, 1, 1, 9, 30),
              kind: BlockKind.anchor,
              locked: false,
            ),
            column: DayColumn(_date),
            controller: const DayScheduleController(),
            edge: ResizeEdge.end,
          );

      container
          .read(resizeStateProvider.notifier)
          .update(DateTime(2000, 1, 1, 10, 15));

      final state = container.read(resizeStateProvider)!;
      expect(state.draftEnd, DateTime(2000, 1, 1, 10));
    });

    test('update on the start edge clamps to the end of the previous block '
        'instead of overlapping it', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(dayBlocksProvider(_date).future);
      await container
          .read(dayBlocksProvider(_date).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 8),
            end: DateTime(2000, 1, 1, 8, 30),
            kind: BlockKind.anchor,
          );
      container
          .read(resizeStateProvider.notifier)
          .start(
            block: TimeObject(
              id: '1',
              title: 'Work',
              start: DateTime(2000, 1, 1, 9),
              end: DateTime(2000, 1, 1, 9, 30),
              kind: BlockKind.anchor,
              locked: false,
            ),
            column: DayColumn(_date),
            controller: const DayScheduleController(),
            edge: ResizeEdge.start,
          );

      container
          .read(resizeStateProvider.notifier)
          .update(DateTime(2000, 1, 1, 8, 15));

      final state = container.read(resizeStateProvider)!;
      expect(state.draftStart, DateTime(2000, 1, 1, 8, 30));
    });

    test('cancel clears the resize without committing', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(dayBlocksProvider(_date).future);
      await container
          .read(dayBlocksProvider(_date).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 9),
            end: DateTime(2000, 1, 1, 9, 30),
            kind: BlockKind.anchor,
          );
      final block = container.read(dayBlocksProvider(_date)).value!.last;
      container
          .read(resizeStateProvider.notifier)
          .start(
            block: block,
            column: DayColumn(_date),
            controller: const DayScheduleController(),
            edge: ResizeEdge.end,
          );
      container
          .read(resizeStateProvider.notifier)
          .update(DateTime(2000, 1, 1, 10));

      container.read(resizeStateProvider.notifier).cancel();

      expect(container.read(resizeStateProvider), isNull);
      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.singleWhere((b) => b.id == block.id).end, block.end);
    });

    test('commit persists the draft start/end via the repository and clears '
        'the resize', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(dayBlocksProvider(_date).future);
      await container
          .read(dayBlocksProvider(_date).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 9),
            end: DateTime(2000, 1, 1, 9, 30),
            kind: BlockKind.anchor,
          );
      final block = container.read(dayBlocksProvider(_date)).value!.last;
      container
          .read(resizeStateProvider.notifier)
          .start(
            block: block,
            column: DayColumn(_date),
            controller: const DayScheduleController(),
            edge: ResizeEdge.end,
          );
      container
          .read(resizeStateProvider.notifier)
          .update(DateTime(2000, 1, 1, 10));

      await container.read(resizeStateProvider.notifier).commit();

      expect(container.read(resizeStateProvider), isNull);
      final blocks = container.read(dayBlocksProvider(_date)).value!;
      final resized = blocks.singleWhere((b) => b.id == block.id);
      expect(resized.start, DateTime(2000, 1, 1, 9));
      expect(resized.end, DateTime(2000, 1, 1, 10));
    });
  });
}
