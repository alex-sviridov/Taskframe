import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/day_schedule_controller.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';

/// Riverpod's `Ref` has no public constructor; reading this trivial
/// provider is the standard way to obtain one from a `ProviderContainer`
/// in a plain (non-widget) test.
final _refProvider = Provider<Ref>((ref) => ref);

/// A test-specific repository that seeds data for test dates.
class _TestDayBlocksRepository extends InMemoryDayBlocksRepository {
  @override
  Future<List<TimeObject>> load(DateTime date) async {
    // Use parent's load, but if this is a test date, ensure seeds exist.
    final parentBlocks = await super.load(date);

    // If loading for test date 2026-09-09 and there are no blocks, add seed blocks.
    if (date.year == 2026 && date.month == 9 && date.day == 9 &&
        parentBlocks.isEmpty) {
      DateTime at(int hour, [int minute = 0]) =>
          DateTime(date.year, date.month, date.day, hour, minute);

      return [
        TimeObject(
          id: 'breakfast',
          title: 'Breakfast',
          start: at(7),
          end: at(7, 30),
          kind: BlockKind.anchor,
          locked: false,
        ),
        TimeObject(
          id: 'commute',
          title: 'Commute',
          start: at(8),
          end: at(8, 30),
          kind: BlockKind.anchor,
          locked: false,
        ),
        TimeObject(
          id: 'work',
          title: 'Work',
          start: at(9),
          end: at(13),
          kind: BlockKind.frame,
          locked: false,
        ),
        TimeObject(
          id: 'lunch',
          title: 'Lunch',
          start: at(13),
          end: at(13, 30),
          kind: BlockKind.anchor,
          locked: false,
        ),
        TimeObject(
          id: 'cleaning',
          title: 'Cleaning',
          start: at(19),
          end: at(20),
          kind: BlockKind.frame,
          locked: false,
        ),
      ];
    }
    return parentBlocks;
  }
}

void main() {
  group('DayScheduleController', () {
    test('blocksOf reads the day blocks provider for the column\'s date', () async {
      final container = ProviderContainer(
        overrides: [
          dayBlocksRepositoryProvider.overrideWithValue(_TestDayBlocksRepository()),
        ],
      );
      addTearDown(container.dispose);
      final ref = container.read(_refProvider);
      const controller = DayScheduleController();
      final date = DateTime(2026, 9, 9);
      await container.read(dayBlocksProvider(date).future);

      final blocks = controller.blocksOf(ref, DayColumn(date));

      expect(blocks, isNotNull);
      expect(blocks!.map((b) => b.id), contains('breakfast'));
    });

    test('blocksOf returns null while the column\'s blocks are still loading', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProvider);
      const controller = DayScheduleController();

      final blocks = controller.blocksOf(ref, DayColumn(DateTime(2026, 9, 9)));

      expect(blocks, isNull);
    });

    test('moveBlock moves the block and refreshes both columns', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ref = container.read(_refProvider);
      const controller = DayScheduleController();
      final fromDate = DateTime(2000, 1, 1);
      final toDate = DateTime(2000, 1, 2);
      await container.read(dayBlocksProvider(fromDate).future);
      final added = await container
          .read(dayBlocksProvider(fromDate).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 10),
            end: DateTime(2000, 1, 1, 10, 30),
            kind: BlockKind.anchor,
          );

      await controller.moveBlock(
        ref,
        block: added,
        fromColumn: DayColumn(fromDate),
        toColumn: DayColumn(toDate),
        newStart: DateTime(2000, 1, 2, 14),
        newEnd: DateTime(2000, 1, 2, 14, 30),
      );

      final fromBlocks = container.read(dayBlocksProvider(fromDate)).value!;
      expect(fromBlocks.where((b) => b.id == added.id), isEmpty);
      final toBlocks = container.read(dayBlocksProvider(toDate)).value!;
      expect(toBlocks.single.id, added.id);
      expect(toBlocks.single.start, DateTime(2000, 1, 2, 14));
    });
  });
}
