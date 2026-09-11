import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/date_key.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// Key in [settingsStore] recording that first-run seeding has already
/// completed — the primary gate for [seedIfEmpty], so deleting all sample
/// data doesn't cause it to silently reappear on a later launch.
const _seedCompletedKey = 'first_run_seed_completed';

/// Writes the app's original hardcoded sample data — today's five seed
/// blocks and the default category — into [db], but only the very first
/// time it ever runs, guarded by a flag record in [settingsStore]. Once
/// that flag is set, this is a no-op forever after, even if the seeded
/// stores are later emptied out again (e.g. a user deleting every sample
/// block) — otherwise seeding would silently re-run on a later launch and
/// stamp the blocks onto whatever day happens to be "today" at that time.
///
/// Each store is also still left untouched once it holds any record, as
/// a defensive belt-and-suspenders check that doesn't clobber existing
/// data — but the flag above is what actually prevents re-seeding.
Future<void> seedIfEmpty(Database db) async {
  final alreadySeeded = await settingsStore.record(_seedCompletedKey).get(db);
  if (alreadySeeded?['value'] == true) return;

  if (await categoriesStore.count(db) == 0) {
    const defaultCategory = Category(
      id: Category.defaultId,
      name: 'Default',
      colorValue: 0xFF009688,
    );
    await categoriesStore.record(defaultCategory.id).put(db, {
      ...defaultCategory.toMap(),
      'order': 0,
    });
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
      await dayBlocksStore.record(block.id).put(db, {
        ...block.toMap(),
        'dateKey': todayKey,
      });
    }
  }

  await settingsStore.record(_seedCompletedKey).put(db, {'value': true});
}
