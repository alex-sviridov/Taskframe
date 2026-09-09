import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';

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
        'block\'s own start', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final block = _block();

      container.read(dragStateProvider.notifier).start(
        block: block,
        originalDate: DateTime(2026, 9, 9),
        pointerGlobalPosition: const Offset(10, 20),
      );

      final state = container.read(dragStateProvider)!;
      expect(state.block, block);
      expect(state.originalDate, DateTime(2026, 9, 9));
      expect(state.targetDate, DateTime(2026, 9, 9));
      expect(state.targetStart, block.start);
      expect(state.pointerGlobalPosition, const Offset(10, 20));
    });

    test('updatePointer moves the pointer without changing target when no '
        'target is given', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(dragStateProvider.notifier).start(
        block: _block(),
        originalDate: DateTime(2026, 9, 9),
        pointerGlobalPosition: const Offset(10, 20),
      );

      container
          .read(dragStateProvider.notifier)
          .updatePointer(const Offset(50, 60));

      final state = container.read(dragStateProvider)!;
      expect(state.pointerGlobalPosition, const Offset(50, 60));
      expect(state.targetDate, DateTime(2026, 9, 9));
    });

    test('updatePointer with a target updates targetDate and targetStart', (
    ) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(dragStateProvider.notifier).start(
        block: _block(),
        originalDate: DateTime(2026, 9, 9),
        pointerGlobalPosition: const Offset(10, 20),
      );

      container.read(dragStateProvider.notifier).updatePointer(
        const Offset(50, 60),
        targetDate: DateTime(2026, 9, 10),
        targetStart: DateTime(2026, 9, 10, 14),
      );

      final state = container.read(dragStateProvider)!;
      expect(state.targetDate, DateTime(2026, 9, 10));
      expect(state.targetStart, DateTime(2026, 9, 10, 14));
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
      container.read(dragStateProvider.notifier).start(
        block: block,
        originalDate: DateTime(2026, 9, 9),
        pointerGlobalPosition: const Offset(10, 20),
      );

      container.read(dragStateProvider.notifier).cancel();

      expect(container.read(dragStateProvider), isNull);
    });

    test('drop moves the block via the repository and clears drag state', (
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final originalDate = DateTime(2026, 9, 9);
      final targetDate = DateTime(2026, 9, 10);
      await container.read(dayBlocksProvider(originalDate).future);
      final added = await container
          .read(dayBlocksProvider(originalDate).notifier)
          .addBlock(
            start: DateTime(2026, 9, 9, 10),
            end: DateTime(2026, 9, 9, 10, 30),
            kind: BlockKind.anchor,
          );
      final block = container
          .read(dayBlocksProvider(originalDate))
          .value!
          .last;

      container.read(dragStateProvider.notifier).start(
        block: block,
        originalDate: originalDate,
        pointerGlobalPosition: const Offset(10, 20),
      );
      container.read(dragStateProvider.notifier).updatePointer(
        const Offset(50, 60),
        targetDate: targetDate,
        targetStart: DateTime(2026, 9, 10, 14),
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
      expect(targetBlocks.single.start, DateTime(2026, 9, 10, 14));
    });
  });
}
