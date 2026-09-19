import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_blocks_provider.dart';
import 'package:taskframe/features/day/day_schedule_controller.dart';
import 'package:taskframe/features/day/drag_state_provider.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';

TimeObject _block() => TimeObject(
  id: '1',
  title: 'Work',
  start: DateTime(2026, 9, 9, 9),
  end: DateTime(2026, 9, 9, 9, 30),
  kind: BlockKind.anchor,
  locked: false,
);

void main() {
  group('dragStateProvider', () {
    test('starts null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(dragStateProvider), isNull);
    });

    test('start sets block, originalDate and initial target to the '
        "block's own start", () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final block = _block();

      container
          .read(dragStateProvider.notifier)
          .start(
            block: block,
            originalColumn: DayColumn(DateTime(2026, 9, 9)),
            controller: const DayScheduleController(),
            pointerGlobalPosition: const Offset(10, 20),
          );

      final state = container.read(dragStateProvider)!;
      expect(state.block, block);
      expect(state.originalColumn, DayColumn(DateTime(2026, 9, 9)));
      expect(state.targetColumn, DayColumn(DateTime(2026, 9, 9)));
      expect(state.targetStart, block.start);
      expect(state.pointerGlobalPosition, const Offset(10, 20));
    });

    test('updatePointer clears the landzone when the pointer is over no '
        'column, so the shadow never contradicts drop-outside-cancels', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(dragStateProvider.notifier)
          .start(
            block: _block(),
            originalColumn: DayColumn(DateTime(2026, 9, 9)),
            controller: const DayScheduleController(),
            pointerGlobalPosition: const Offset(10, 20),
          );
      expect(container.read(dragStateProvider)!.hasTarget, isTrue);

      container
          .read(dragStateProvider.notifier)
          .updatePointer(const Offset(50, 60));

      final state = container.read(dragStateProvider)!;
      expect(state.pointerGlobalPosition, const Offset(50, 60));
      expect(state.targetColumn, isNull);
      expect(state.targetStart, isNull);
      expect(state.hasTarget, isFalse);
    });

    test('drop with no landzone cancels instead of moving the block', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final originalDate = DateTime(2026, 9, 9);
      await container.read(dayBlocksProvider(originalDate).future);
      await container
          .read(dayBlocksProvider(originalDate).notifier)
          .addBlock(
            start: DateTime(2026, 9, 9, 10),
            end: DateTime(2026, 9, 9, 10, 30),
            kind: BlockKind.anchor,
          );
      final block = container.read(dayBlocksProvider(originalDate)).value!.last;

      container
          .read(dragStateProvider.notifier)
          .start(
            block: block,
            originalColumn: DayColumn(originalDate),
            controller: const DayScheduleController(),
            pointerGlobalPosition: const Offset(10, 20),
          );
      container
          .read(dragStateProvider.notifier)
          .updatePointer(const Offset(50, 60));

      await container.read(dragStateProvider.notifier).drop();

      expect(container.read(dragStateProvider), isNull);
      final blocks = container.read(dayBlocksProvider(originalDate)).value!;
      expect(blocks.singleWhere((b) => b.id == block.id).start, block.start);
    });

    test('updatePointer with a target updates targetDate and targetStart', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(dragStateProvider.notifier)
          .start(
            block: _block(),
            originalColumn: DayColumn(DateTime(2026, 9, 9)),
            controller: const DayScheduleController(),
            pointerGlobalPosition: const Offset(10, 20),
          );

      container
          .read(dragStateProvider.notifier)
          .updatePointer(
            const Offset(50, 60),
            targetColumn: DayColumn(DateTime(2026, 9, 10)),
            targetStart: DateTime(2026, 9, 10, 14),
          );

      final state = container.read(dragStateProvider)!;
      expect(state.targetColumn, DayColumn(DateTime(2026, 9, 10)));
      expect(state.targetStart, DateTime(2026, 9, 10, 14));
    });

    test('updatePointer falls back to the original position when the target '
        'overlaps an existing block', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final targetDate = DateTime(2026, 9, 10);
      await container.read(dayBlocksProvider(targetDate).future);
      await container
          .read(dayBlocksProvider(targetDate).notifier)
          .addBlock(
            start: DateTime(2026, 9, 10, 14),
            end: DateTime(2026, 9, 10, 14, 30),
            kind: BlockKind.anchor,
          );
      final dragged = _block();
      container
          .read(dragStateProvider.notifier)
          .start(
            block: dragged,
            originalColumn: DayColumn(DateTime(2026, 9, 9)),
            controller: const DayScheduleController(),
            pointerGlobalPosition: const Offset(10, 20),
          );

      container
          .read(dragStateProvider.notifier)
          .updatePointer(
            const Offset(50, 60),
            targetColumn: DayColumn(targetDate),
            // overlaps the existing 14:00-14:30 block
            targetStart: DateTime(2026, 9, 10, 14, 15),
          );

      final state = container.read(dragStateProvider)!;
      expect(state.targetColumn, DayColumn(DateTime(2026, 9, 9)));
      expect(state.targetStart, dragged.start);
    });

    test('updatePointer does nothing when no drag is in progress', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(dragStateProvider.notifier)
          .updatePointer(const Offset(50, 60));

      expect(container.read(dragStateProvider), isNull);
    });

    test('cancel clears the drag without moving the block', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final block = _block();
      await container.read(dayBlocksProvider(DateTime(2026, 9, 9)).future);
      container
          .read(dragStateProvider.notifier)
          .start(
            block: block,
            originalColumn: DayColumn(DateTime(2026, 9, 9)),
            controller: const DayScheduleController(),
            pointerGlobalPosition: const Offset(10, 20),
          );

      container.read(dragStateProvider.notifier).cancel();

      expect(container.read(dragStateProvider), isNull);
    });

    test(
      'drop moves the block via the repository and clears drag state',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        // Fixed, far-past dates: InMemoryDayBlocksRepository seeds hardcoded
        // blocks for whatever date happens to be "today", so a target date
        // must never risk coinciding with the real calendar date the test
        // suite runs on.
        final originalDate = DateTime(2000);
        final targetDate = DateTime(2000, 1, 2);
        await container.read(dayBlocksProvider(originalDate).future);
        await container
            .read(dayBlocksProvider(originalDate).notifier)
            .addBlock(
              start: DateTime(2000, 1, 1, 10),
              end: DateTime(2000, 1, 1, 10, 30),
              kind: BlockKind.anchor,
            );
        final block = container
            .read(dayBlocksProvider(originalDate))
            .value!
            .last;

        container
            .read(dragStateProvider.notifier)
            .start(
              block: block,
              originalColumn: DayColumn(originalDate),
              controller: const DayScheduleController(),
              pointerGlobalPosition: const Offset(10, 20),
            );
        container
            .read(dragStateProvider.notifier)
            .updatePointer(
              const Offset(50, 60),
              targetColumn: DayColumn(targetDate),
              targetStart: DateTime(2000, 1, 2, 14),
            );

        await container.read(dragStateProvider.notifier).drop();

        expect(container.read(dragStateProvider), isNull);
        final originalBlocks = container
            .read(dayBlocksProvider(originalDate))
            .value!;
        expect(originalBlocks.where((b) => b.id == block.id), isEmpty);
        final targetBlocks = container
            .read(dayBlocksProvider(targetDate))
            .value!;
        expect(targetBlocks.single.id, block.id);
        expect(targetBlocks.single.start, DateTime(2000, 1, 2, 14));
      },
    );
  });
}
