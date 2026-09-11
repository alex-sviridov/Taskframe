import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/date_key.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// Writes the app's original hardcoded sample data — today's five seed
/// blocks and the default category — into [db], but only the first time
/// it runs: each store is left untouched once it holds any record, so
/// this never overwrites real data on later launches.
Future<void> seedIfEmpty(Database db) async {
  if (await categoriesStore.count(db) == 0) {
    const defaultCategory = Category(
      id: Category.defaultId,
      name: 'Default',
      colorValue: 0xFF009688,
    );
    await categoriesStore
        .record(defaultCategory.id)
        .put(db, {...defaultCategory.toMap(), 'order': 0});
  }

  if (await dayBlocksStore.count(db) == 0) {
    final today = DateTime.now();
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(today.year, today.month, today.day, hour, minute);

    final seedBlocks = [
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

    final todayKey = dateKeyFor(today);
    for (final block in seedBlocks) {
      await dayBlocksStore
          .record(block.id)
          .put(db, {...block.toMap(), 'dateKey': todayKey});
    }
  }
}
