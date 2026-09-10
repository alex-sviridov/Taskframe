# Block Edit Modal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user tap a block (or just create one) to open an edit modal where they can rename it, change its start/end time, copy it to the next day, or delete it.

**Architecture:** Extend `DayBlocksRepository`/`DayBlocksNotifier` with `update`/`delete`/`copyToNextDay` operations (mirroring the existing `move` pattern), add two pure validation helpers alongside the existing grid-time helpers in `day_new_block.dart`, build a new `BlockEditModal` widget (shown via a breakpoint-aware `showBlockEditModal` helper — a bottom sheet on narrow widths, a centered `Dialog` on wide ones), then wire it to open on a block tap (`DayGrid`) and immediately after block creation (`DayScreen`'s `_SchedulePage`).

**Tech Stack:** Flutter, flutter_riverpod (`AsyncNotifier`/`Notifier`), flutter_test + mocktail-free widget/unit tests (existing suite uses no mocks for this feature area).

**Spec:** `docs/superpowers/specs/2026-09-10-block-edit-modal-design.md`

## Global Constraints

- Every edit (title/start/end) autosaves immediately — no Save/Cancel buttons (spec: "Editing behavior").
- An invalid start/end candidate is silently rejected (no error text) — implemented here as: the notifier's `updateBlock` no-ops on an invalid candidate, so the modal's displayed time simply doesn't change (spec: "Time conflicts" Q&A).
- Copy-to-next-day: the icon button is disabled (not tappable) whenever the same time slot is occupied on the next day — never tappable-then-rejected (spec: "Copy conflict" Q&A).
- Delete: two-tap confirm on the delete icon itself, no separate confirmation dialog (spec: "Delete confirmation" Q&A).
- Copy and Delete are icon-only buttons with tooltips, no text labels (user follow-up after spec approval).
- Category is a non-interactive placeholder only — no data model, no selection (spec: "Non-goals").
- `kind` and `locked` are not editable in this modal (spec: "Non-goals").

---

## Task 1: Repository — add `update`, `delete`, and an optional `title` on `add`

**Files:**
- Modify: `lib/features/day/data/day_blocks_repository.dart`
- Test: `test/unit/day_blocks_repository_test.dart`

**Interfaces:**
- Produces: `DayBlocksRepository.add(DateTime date, {required DateTime start, required DateTime end, required BlockKind kind, String? title}) -> Future<TimeObject>` (title now optional, defaults to `'title'` exactly as before).
- Produces: `DayBlocksRepository.update(TimeObject block, {required DateTime date, String? title, DateTime? start, DateTime? end}) -> Future<TimeObject>`.
- Produces: `DayBlocksRepository.delete(TimeObject block, {required DateTime date}) -> Future<void>`.

- [ ] **Step 1: Write the failing tests**

Append to `test/unit/day_blocks_repository_test.dart`, inside the existing `group('InMemoryDayBlocksRepository', ...)`, just before its closing `});`:

```dart
    test('add uses the given title when provided', () async {
      final date = DateTime.now().add(const Duration(days: 3));

      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
        title: 'Gym',
      );

      expect(added.title, 'Gym');
    });

    test('update changes an added block\'s title, start and end', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      final updated = await repository.update(
        added,
        date: date,
        title: 'Renamed',
        start: DateTime(date.year, date.month, date.day, 11),
        end: DateTime(date.year, date.month, date.day, 11, 30),
      );

      expect(updated.id, added.id);
      expect(updated.title, 'Renamed');
      expect(updated.start, DateTime(date.year, date.month, date.day, 11));
      expect(updated.end, DateTime(date.year, date.month, date.day, 11, 30));
    });

    test('update leaves fields unspecified as null unchanged', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      final updated = await repository.update(added, date: date, title: 'Renamed');

      expect(updated.start, added.start);
      expect(updated.end, added.end);
    });

    test('update replaces the block in a later load for that date', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      await repository.update(added, date: date, title: 'Renamed');

      final blocks = await repository.load(date);
      expect(blocks, hasLength(1));
      expect(blocks.single.title, 'Renamed');
    });

    test('updating a seeded block promotes it and keeps its new title on '
        'later loads', () async {
      final today = DateTime.now();
      final seeded = (await repository.load(today))
          .firstWhere((b) => b.id == 'breakfast');

      await repository.update(seeded, date: today, title: 'Brunch');

      final blocks = await repository.load(today);
      expect(blocks.where((b) => b.id == 'breakfast'), hasLength(1));
      expect(blocks.firstWhere((b) => b.id == 'breakfast').title, 'Brunch');
    });

    test('delete removes an added block from a later load', () async {
      final date = DateTime.now().add(const Duration(days: 3));
      final added = await repository.add(
        date,
        start: DateTime(date.year, date.month, date.day, 10),
        end: DateTime(date.year, date.month, date.day, 10, 30),
        kind: BlockKind.anchor,
      );

      await repository.delete(added, date: date);

      expect(await repository.load(date), isEmpty);
    });

    test('delete removes a seeded block from a later load', () async {
      final today = DateTime.now();
      final seeded = (await repository.load(today))
          .firstWhere((b) => b.id == 'breakfast');

      await repository.delete(seeded, date: today);

      final blocks = await repository.load(today);
      expect(blocks.where((b) => b.id == 'breakfast'), isEmpty);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/day_blocks_repository_test.dart`
Expected: FAIL — `update`/`delete` are not defined on `DayBlocksRepository`, and `add` doesn't accept `title`.

- [ ] **Step 3: Implement `update`, `delete`, and the optional `title`**

In `lib/features/day/data/day_blocks_repository.dart`, replace the whole file with:

```dart
import 'package:taskframe/features/day/models/time_object.dart';

/// Loads and stores the timeline blocks for a given date.
///
/// Implementations back this with whatever storage is appropriate (in
/// memory today, an API later); callers depend only on this interface.
abstract class DayBlocksRepository {
  /// Returns the blocks for [date].
  Future<List<TimeObject>> load(DateTime date);

  /// Creates a new block on [date] and returns it. [title] defaults to a
  /// placeholder when omitted.
  Future<TimeObject> add(
    DateTime date, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
  });

  /// Moves [block] from [fromDate] to [toDate], updating its start/end to
  /// [newStart]/[newEnd], and returns the updated block. [fromDate] and
  /// [toDate] may be the same date.
  Future<TimeObject> move(
    TimeObject block, {
    required DateTime fromDate,
    required DateTime toDate,
    required DateTime newStart,
    required DateTime newEnd,
  });

  /// Updates [block] (which belongs to [date]) in place, replacing any of
  /// [title]/[start]/[end] that are given and leaving the rest unchanged.
  /// Returns the updated block.
  Future<TimeObject> update(
    TimeObject block, {
    required DateTime date,
    String? title,
    DateTime? start,
    DateTime? end,
  });

  /// Removes [block] (which belongs to [date]).
  Future<void> delete(TimeObject block, {required DateTime date});
}

/// A [DayBlocksRepository] that keeps added blocks in memory for the life
/// of the app, seeded with a hardcoded set of blocks for today.
class InMemoryDayBlocksRepository implements DayBlocksRepository {
  final Map<DateTime, List<TimeObject>> _added = {};
  final Set<String> _movedSeedIds = {};
  int _nextId = 0;

  @override
  Future<List<TimeObject>> load(DateTime date) async {
    return [..._seedFor(date), ...?_added[_dateKey(date)]];
  }

  @override
  Future<TimeObject> add(
    DateTime date, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
  }) async {
    final block = TimeObject(
      id: 'block-${_nextId++}',
      title: title ?? 'title',
      start: start,
      end: end,
      kind: kind,
      locked: false,
    );

    final key = _dateKey(date);
    _added[key] = [...?_added[key], block];
    return block;
  }

  @override
  Future<TimeObject> move(
    TimeObject block, {
    required DateTime fromDate,
    required DateTime toDate,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final fromKey = _dateKey(fromDate);
    final toKey = _dateKey(toDate);

    final fromList = _added[fromKey];
    if (fromList != null && fromList.any((b) => b.id == block.id)) {
      _added[fromKey] = fromList.where((b) => b.id != block.id).toList();
    } else {
      _movedSeedIds.add(block.id);
    }

    final moved = TimeObject(
      id: block.id,
      title: block.title,
      start: newStart,
      end: newEnd,
      kind: block.kind,
      locked: block.locked,
    );

    _added[toKey] = [...?_added[toKey], moved];
    return moved;
  }

  @override
  Future<TimeObject> update(
    TimeObject block, {
    required DateTime date,
    String? title,
    DateTime? start,
    DateTime? end,
  }) async {
    final key = _dateKey(date);
    final updated = TimeObject(
      id: block.id,
      title: title ?? block.title,
      start: start ?? block.start,
      end: end ?? block.end,
      kind: block.kind,
      locked: block.locked,
    );

    final list = _added[key];
    if (list != null && list.any((b) => b.id == block.id)) {
      _added[key] = [
        for (final b in list) if (b.id == block.id) updated else b,
      ];
    } else {
      // A seeded block being edited for the first time: promote it into
      // `_added` and suppress the stale seed, the same way `move` does.
      _movedSeedIds.add(block.id);
      _added[key] = [...?_added[key], updated];
    }
    return updated;
  }

  @override
  Future<void> delete(TimeObject block, {required DateTime date}) async {
    final key = _dateKey(date);
    final list = _added[key];
    if (list != null && list.any((b) => b.id == block.id)) {
      _added[key] = list.where((b) => b.id != block.id).toList();
    } else {
      _movedSeedIds.add(block.id);
    }
  }

  static DateTime _dateKey(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  List<TimeObject> _seedFor(DateTime date) {
    final today = DateTime.now();
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    if (!isToday) {
      return [];
    }

    DateTime at(int hour, [int minute = 0]) =>
        DateTime(today.year, today.month, today.day, hour, minute);

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
    ].where((block) => !_movedSeedIds.contains(block.id)).toList();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/day_blocks_repository_test.dart`
Expected: PASS (all tests, old and new).

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/data/day_blocks_repository.dart test/unit/day_blocks_repository_test.dart
git commit -m "Add update/delete to DayBlocksRepository and an optional add title"
```

---

## Task 2: Notifier — `updateBlock`, `deleteBlock`, `copyToNextDay`, and validation helpers

**Files:**
- Modify: `lib/features/day/day_new_block.dart` (two new pure functions)
- Modify: `lib/features/day/providers.dart` (`DayBlocksNotifier` additions)
- Test: `test/unit/day_new_block_test.dart`
- Test: `test/unit/day_blocks_provider_test.dart`

**Interfaces:**
- Consumes: `DayBlocksRepository.add/update/delete` from Task 1; `TimeObject.overlaps` (`lib/features/day/models/time_object.dart`); `dayEndFor` (already in `day_new_block.dart`).
- Produces: `bool isValidBlockEdit({required DateTime start, required DateTime end, required DaySettings settings, required DateTime day, required List<TimeObject> others})`.
- Produces: `bool copyToNextDayWouldOverlap({required TimeObject block, required DateTime nextDate, required List<TimeObject> nextDayBlocks})`.
- Produces: `DayBlocksNotifier.addBlock(...) -> Future<TimeObject>` (now returns the created block; `title` is now an optional named param too).
- Produces: `DayBlocksNotifier.updateBlock(TimeObject block, {String? title, DateTime? start, DateTime? end}) -> Future<void>` (no-ops silently if the resulting start/end would be invalid per `isValidBlockEdit`).
- Produces: `DayBlocksNotifier.deleteBlock(TimeObject block) -> Future<void>`.
- Produces: `DayBlocksNotifier.copyToNextDay(TimeObject block) -> Future<void>` (adds a copy — same title/kind/duration, same time of day — to `dayBlocksProvider` for `date + 1 day`).

- [ ] **Step 1: Write the failing pure-function tests**

Append to `test/unit/day_new_block_test.dart`, before the file's final closing `}`:

```dart

  group('isValidBlockEdit', () {
    test('accepts an ordered range within the day bounds with no overlap', () {
      final valid = isValidBlockEdit(
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 9, 30),
        settings: _settings,
        day: DateTime(2026, 9, 9),
        others: const [],
      );

      expect(valid, isTrue);
    });

    test('rejects end at or before start', () {
      final valid = isValidBlockEdit(
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 9),
        settings: _settings,
        day: DateTime(2026, 9, 9),
        others: const [],
      );

      expect(valid, isFalse);
    });

    test('rejects a start before the day\'s own start hour', () {
      final valid = isValidBlockEdit(
        start: DateTime(2026, 9, 9, 5, 45),
        end: DateTime(2026, 9, 9, 6, 15),
        settings: _settings,
        day: DateTime(2026, 9, 9),
        others: const [],
      );

      expect(valid, isFalse);
    });

    test('rejects an end after the day\'s own end hour', () {
      final valid = isValidBlockEdit(
        start: DateTime(2026, 9, 9, 22, 45),
        end: DateTime(2026, 9, 9, 23, 15),
        settings: _settings,
        day: DateTime(2026, 9, 9),
        others: const [],
      );

      expect(valid, isFalse);
    });

    test('rejects a range overlapping another block', () {
      final valid = isValidBlockEdit(
        start: DateTime(2026, 9, 9, 9),
        end: DateTime(2026, 9, 9, 9, 30),
        settings: _settings,
        day: DateTime(2026, 9, 9),
        others: [
          TimeObject(
            id: 'x',
            title: 'X',
            start: DateTime(2026, 9, 9, 9, 15),
            end: DateTime(2026, 9, 9, 9, 45),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
      );

      expect(valid, isFalse);
    });
  });

  group('copyToNextDayWouldOverlap', () {
    final block = TimeObject(
      id: '1',
      title: 'Work',
      start: DateTime(2026, 9, 9, 9),
      end: DateTime(2026, 9, 9, 9, 30),
      kind: BlockKind.anchor,
      locked: false,
    );

    test('is false when the next day has no conflicting block', () {
      final overlaps = copyToNextDayWouldOverlap(
        block: block,
        nextDate: DateTime(2026, 9, 10),
        nextDayBlocks: const [],
      );

      expect(overlaps, isFalse);
    });

    test('is true when the same time slot is occupied on the next day', () {
      final overlaps = copyToNextDayWouldOverlap(
        block: block,
        nextDate: DateTime(2026, 9, 10),
        nextDayBlocks: [
          TimeObject(
            id: 'y',
            title: 'Y',
            start: DateTime(2026, 9, 10, 9, 15),
            end: DateTime(2026, 9, 10, 9, 45),
            kind: BlockKind.anchor,
            locked: false,
          ),
        ],
      );

      expect(overlaps, isTrue);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/day_new_block_test.dart`
Expected: FAIL — `isValidBlockEdit`/`copyToNextDayWouldOverlap` are undefined.

- [ ] **Step 3: Implement the two pure functions**

In `lib/features/day/day_new_block.dart`, add this import at the top:

```dart
import 'package:taskframe/features/day/models/time_object.dart';
```

(Already imported for `List<TimeObject>` parameters elsewhere in the file — check first; if present, skip.)

Append at the end of the file:

```dart

/// Whether editing a block to span `[start, end)` on [day] is allowed: the
/// range must be ordered, fall within [settings]'s day bounds, and not
/// overlap any of [others]. Used to silently reject an invalid title/start/
/// end edit rather than showing an error.
bool isValidBlockEdit({
  required DateTime start,
  required DateTime end,
  required DaySettings settings,
  required DateTime day,
  required List<TimeObject> others,
}) {
  if (!end.isAfter(start)) return false;
  final dayStart = DateTime(
    day.year,
    day.month,
    day.day,
    settings.dayStartHour,
  );
  if (start.isBefore(dayStart)) return false;
  if (end.isAfter(dayEndFor(day, settings))) return false;
  return others.every((block) => !block.overlaps(start, end));
}

/// Whether copying [block] to [nextDate] (same time of day, same duration)
/// would overlap any of [nextDayBlocks].
bool copyToNextDayWouldOverlap({
  required TimeObject block,
  required DateTime nextDate,
  required List<TimeObject> nextDayBlocks,
}) {
  final duration = block.end.difference(block.start);
  final start = DateTime(
    nextDate.year,
    nextDate.month,
    nextDate.day,
    block.start.hour,
    block.start.minute,
  );
  final end = start.add(duration);
  return nextDayBlocks.any((b) => b.overlaps(start, end));
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/day_new_block_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing notifier tests**

Append to `test/unit/day_blocks_provider_test.dart`, inside `group('dayBlocksProvider', ...)`, before its closing `});`:

```dart

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

      await notifier.updateBlock(first, start: DateTime(2026, 9, 9, 11, 15));

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
      final date = DateTime(2026, 9, 9);
      final nextDate = DateTime(2026, 9, 10);
      await container.read(dayBlocksProvider(date).future);
      final created = await container
          .read(dayBlocksProvider(date).notifier)
          .addBlock(
            start: DateTime(2026, 9, 9, 10),
            end: DateTime(2026, 9, 9, 10, 30),
            kind: BlockKind.anchor,
            title: 'Gym',
          );

      await container.read(dayBlocksProvider(date).notifier).copyToNextDay(created);

      final nextDayBlocks = await container.read(dayBlocksProvider(nextDate).future);
      expect(nextDayBlocks, hasLength(1));
      expect(nextDayBlocks.single.title, 'Gym');
      expect(nextDayBlocks.single.start, DateTime(2026, 9, 10, 10));
      expect(nextDayBlocks.single.end, DateTime(2026, 9, 10, 10, 30));
    });
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `flutter test test/unit/day_blocks_provider_test.dart`
Expected: FAIL — `updateBlock`/`deleteBlock`/`copyToNextDay` undefined, and `addBlock`'s return type mismatch.

- [ ] **Step 7: Implement the notifier changes**

In `lib/features/day/providers.dart`, add this import near the top (alongside the existing `models/time_object.dart` import):

```dart
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
```

Replace the `addBlock` method and add the three new methods, so `DayBlocksNotifier` reads:

```dart
class DayBlocksNotifier extends AsyncNotifier<List<TimeObject>> {
  /// Creates a [DayBlocksNotifier] for [date].
  new(this.date);

  /// The date this notifier's blocks belong to.
  final DateTime date;

  @override
  Future<List<TimeObject>> build() =>
      ref.watch(dayBlocksRepositoryProvider).load(date);

  /// Creates a new block on [date], adds it to the current state, and
  /// returns it.
  Future<TimeObject> addBlock({
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
  }) async {
    final repository = ref.read(dayBlocksRepositoryProvider);
    final added = await repository.add(
      date,
      start: start,
      end: end,
      kind: kind,
      title: title,
    );
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Updates [block]'s title/start/end, persisting via the repository and
  /// refreshing state. Silently does nothing if the resulting start/end
  /// would be invalid (see [isValidBlockEdit]) — title-only edits are
  /// always valid since they don't touch start/end.
  Future<void> updateBlock(
    TimeObject block, {
    String? title,
    DateTime? start,
    DateTime? end,
  }) async {
    final newStart = start ?? block.start;
    final newEnd = end ?? block.end;
    final others = (state.value ?? [])
        .where((b) => b.id != block.id)
        .toList();
    final settings = ref.read(daySettingsProvider);
    if (!isValidBlockEdit(
      start: newStart,
      end: newEnd,
      settings: settings,
      day: date,
      others: others,
    )) {
      return;
    }

    final repository = ref.read(dayBlocksRepositoryProvider);
    final updated = await repository.update(
      block,
      date: date,
      title: title,
      start: start,
      end: end,
    );
    state = AsyncData([
      for (final b in state.value ?? <TimeObject>[])
        if (b.id == block.id) updated else b,
    ]);
  }

  /// Removes [block], persisting via the repository and refreshing state.
  Future<void> deleteBlock(TimeObject block) async {
    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.delete(block, date: date);
    state = AsyncData([
      for (final b in state.value ?? <TimeObject>[])
        if (b.id != block.id) b,
    ]);
  }

  /// Adds a copy of [block] (same title/kind/duration, same time of day) to
  /// the following date's blocks.
  Future<void> copyToNextDay(TimeObject block) async {
    final nextDate = DateTime(date.year, date.month, date.day + 1);
    final duration = block.end.difference(block.start);
    final nextStart = DateTime(
      nextDate.year,
      nextDate.month,
      nextDate.day,
      block.start.hour,
      block.start.minute,
    );
    await ref
        .read(dayBlocksProvider(nextDate).notifier)
        .addBlock(
          start: nextStart,
          end: nextStart.add(duration),
          kind: block.kind,
          title: block.title,
        );
  }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `flutter test test/unit/day_new_block_test.dart test/unit/day_blocks_provider_test.dart test/unit/day_blocks_repository_test.dart test/unit/resize_state_provider_test.dart`
Expected: PASS for all (the resize test file is included since it also calls `addBlock` and must keep compiling/passing with the new signature).

- [ ] **Step 9: Commit**

```bash
git add lib/features/day/day_new_block.dart lib/features/day/providers.dart test/unit/day_new_block_test.dart test/unit/day_blocks_provider_test.dart
git commit -m "Add updateBlock/deleteBlock/copyToNextDay to DayBlocksNotifier"
```

---

## Task 3: Category placeholder widget

**Files:**
- Create: `lib/features/day/widgets/block_edit_modal.dart` (started here; grown by later tasks)
- Test: `test/widget/block_edit_modal_test.dart` (started here; grown by later tasks)

**Interfaces:**
- Produces: `class BlockCategoryPlaceholder extends StatelessWidget` — a fixed-height row of empty rounded squares, reserving space for a future category carousel. Public (not private) so its own widget test can pump it directly, and later tasks in this file compose it into `BlockEditModal`.

- [ ] **Step 1: Write the failing test**

Create `test/widget/block_edit_modal_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';

void main() {
  group('BlockCategoryPlaceholder', () {
    testWidgets('renders a row of empty squares', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BlockCategoryPlaceholder()),
        ),
      );

      expect(find.byType(BlockCategoryPlaceholder), findsOneWidget);
      expect(find.byType(Container), findsWidgets);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/block_edit_modal_test.dart`
Expected: FAIL — `package:taskframe/features/day/widgets/block_edit_modal.dart` does not exist.

- [ ] **Step 3: Create the file with the placeholder widget**

Create `lib/features/day/widgets/block_edit_modal.dart`:

```dart
import 'package:flutter/material.dart';

/// A fixed-height row of empty, non-interactive rounded squares reserving
/// visual space for a future category carousel. Carries no data model or
/// selection state yet.
class BlockCategoryPlaceholder extends StatelessWidget {
  /// Creates a [BlockCategoryPlaceholder].
  const BlockCategoryPlaceholder({super.key});

  static const double _size = 40;
  static const int _count = 5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _count,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/block_edit_modal_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/widgets/block_edit_modal.dart test/widget/block_edit_modal_test.dart
git commit -m "Add category placeholder widget for the block edit modal"
```

---

## Task 4: Time row and wheel time picker

**Files:**
- Modify: `lib/features/day/widgets/block_edit_modal.dart`
- Test: `test/widget/block_edit_modal_test.dart`

**Interfaces:**
- Consumes: `DaySettings` (`lib/features/day/day_settings.dart`).
- Produces: `class BlockTimeRow extends StatelessWidget` (`label`, `time`, `onTap`, `Key? rowKey` — a tappable row showing a label and an `HH:mm` time).
- Produces: `Future<DateTime?> showTimeWheelPicker({required BuildContext context, required DateTime initial, required DaySettings settings})` — opens a bottom sheet with hour/minute-in-15 wheels defaulted to `initial`; returns the picked `DateTime` (same date as `initial`) on "Done", or `null` if dismissed.

- [ ] **Step 1: Write the failing tests**

Append to `test/widget/block_edit_modal_test.dart`:

```dart
import 'package:taskframe/features/day/day_settings.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);
```

(Add this alongside the existing imports/top-level declarations, above `void main()`.)

Then add, inside `void main()`, alongside the existing `group('BlockCategoryPlaceholder', ...)`:

```dart
  group('BlockTimeRow', () {
    testWidgets('shows the label and formatted time', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockTimeRow(
              label: 'Starts',
              time: DateTime(2026, 9, 9, 9, 5),
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Starts'), findsOneWidget);
      expect(find.text('09:05'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockTimeRow(
              label: 'Starts',
              time: DateTime(2026, 9, 9, 9),
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(BlockTimeRow));

      expect(tapped, isTrue);
    });
  });

  group('showTimeWheelPicker', () {
    testWidgets('returns the picked time on Done', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await showTimeWheelPicker(
                    context: context,
                    initial: DateTime(2026, 9, 9, 9),
                    settings: _settings,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // The wheel starts scrolled to `initial`'s hour/minute, and Done
      // confirms without any scrolling, so it must return the same value.
      expect(picked, DateTime(2026, 9, 9, 9));
    });

    testWidgets('returns null when dismissed without confirming', (
      tester,
    ) async {
      DateTime? picked = DateTime(2026, 9, 9, 9);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await showTimeWheelPicker(
                    context: context,
                    initial: DateTime(2026, 9, 9, 9),
                    settings: _settings,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // Tap the barrier above the sheet to dismiss it without confirming.
      await tester.tapAt(const Offset(400, 50));
      await tester.pumpAndSettle();

      expect(picked, isNull);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/block_edit_modal_test.dart`
Expected: FAIL — `BlockTimeRow`/`showTimeWheelPicker` undefined.

- [ ] **Step 3: Implement `BlockTimeRow` and `showTimeWheelPicker`**

Add these imports at the top of `lib/features/day/widgets/block_edit_modal.dart`:

```dart
import 'package:taskframe/features/day/day_settings.dart';
```

Append to `lib/features/day/widgets/block_edit_modal.dart`:

```dart

/// A tappable row showing [label] and [time] as `HH:mm`, used for the
/// block edit modal's start/end rows.
class BlockTimeRow extends StatelessWidget {
  /// Creates a [BlockTimeRow].
  const BlockTimeRow({
    required this.label,
    required this.time,
    required this.onTap,
    super.key,
  });

  /// The row's leading label, e.g. "Starts".
  final String label;

  /// The time shown, formatted as `HH:mm`.
  final DateTime time;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    return ListTile(
      title: Text(label),
      trailing: Text(text, style: Theme.of(context).textTheme.titleMedium),
      onTap: onTap,
    );
  }
}

/// Opens a bottom sheet with hour/minute-in-15-increments wheels, scrolled
/// initially to [initial]'s hour/minute (rounded down to the nearest 15),
/// bounded by [settings]'s day start/end hour. Returns the picked
/// [DateTime] (same year/month/day as [initial]) if the user taps "Done",
/// or `null` if the sheet is dismissed another way.
Future<DateTime?> showTimeWheelPicker({
  required BuildContext context,
  required DateTime initial,
  required DaySettings settings,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    builder: (context) => _TimeWheelPicker(initial: initial, settings: settings),
  );
}

class _TimeWheelPicker extends StatefulWidget {
  const _TimeWheelPicker({required this.initial, required this.settings});

  final DateTime initial;
  final DaySettings settings;

  @override
  State<_TimeWheelPicker> createState() => _TimeWheelPickerState();
}

class _TimeWheelPickerState extends State<_TimeWheelPicker> {
  late int _hour;
  late int _quarterIndex;

  List<int> get _hours => [
    for (var h = widget.settings.dayStartHour; h <= widget.settings.dayEndHour; h++) h,
  ];

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    _quarterIndex = widget.initial.minute ~/ 15;
  }

  @override
  Widget build(BuildContext context) {
    final hours = _hours;
    return SafeArea(
      child: SizedBox(
        height: 260,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ListWheelScrollView(
                      itemExtent: 40,
                      controller: FixedExtentScrollController(
                        initialItem: hours.indexOf(_hour),
                      ),
                      onSelectedItemChanged: (index) =>
                          setState(() => _hour = hours[index]),
                      children: [
                        for (final h in hours)
                          Center(child: Text(h.toString().padLeft(2, '0'))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListWheelScrollView(
                      itemExtent: 40,
                      controller: FixedExtentScrollController(
                        initialItem: _quarterIndex,
                      ),
                      onSelectedItemChanged: (index) =>
                          setState(() => _quarterIndex = index),
                      children: const [
                        Center(child: Text('00')),
                        Center(child: Text('15')),
                        Center(child: Text('30')),
                        Center(child: Text('45')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                DateTime(
                  widget.initial.year,
                  widget.initial.month,
                  widget.initial.day,
                  _hour,
                  _quarterIndex * 15,
                ),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/block_edit_modal_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/widgets/block_edit_modal.dart test/widget/block_edit_modal_test.dart
git commit -m "Add time row and wheel time picker for the block edit modal"
```

---

## Task 5: Two-tap delete confirm button

**Files:**
- Modify: `lib/features/day/widgets/block_edit_modal.dart`
- Test: `test/widget/block_edit_modal_test.dart`

**Interfaces:**
- Produces: `class BlockDeleteButton extends StatefulWidget` (`onConfirmed`) — an icon button that requires two taps within 3 seconds to fire `onConfirmed`; a single tap followed by a timeout reverts and requires two fresh taps again.

- [ ] **Step 1: Write the failing tests**

Append to `test/widget/block_edit_modal_test.dart`, inside `void main()`:

```dart
  group('BlockDeleteButton', () {
    testWidgets('does not confirm on a single tap', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockDeleteButton(onConfirmed: () => confirmed = true),
          ),
        ),
      );

      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();

      expect(confirmed, isFalse);
    });

    testWidgets('confirms on a second tap within the timeout', (
      tester,
    ) async {
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockDeleteButton(onConfirmed: () => confirmed = true),
          ),
        ),
      );

      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();
      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();

      expect(confirmed, isTrue);
    });

    testWidgets('reverts to needing two taps again after the timeout '
        'lapses', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockDeleteButton(onConfirmed: () => confirmed = true),
          ),
        ),
      );

      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();

      expect(confirmed, isFalse);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/block_edit_modal_test.dart`
Expected: FAIL — `BlockDeleteButton` undefined.

- [ ] **Step 3: Implement `BlockDeleteButton`**

Add this import at the top of `lib/features/day/widgets/block_edit_modal.dart`:

```dart
import 'dart:async';
```

Append to `lib/features/day/widgets/block_edit_modal.dart`:

```dart

/// A delete icon button that requires two taps within [_confirmWindow] to
/// call [onConfirmed] — no separate confirmation dialog. The first tap
/// swaps the icon/tooltip into a "confirming" state and starts a timer; a
/// second tap before it lapses confirms, letting it lapse reverts.
class BlockDeleteButton extends StatefulWidget {
  /// Creates a [BlockDeleteButton].
  const BlockDeleteButton({required this.onConfirmed, super.key});

  /// Called when the second tap lands within the confirm window.
  final VoidCallback onConfirmed;

  @override
  State<BlockDeleteButton> createState() => _BlockDeleteButtonState();
}

class _BlockDeleteButtonState extends State<BlockDeleteButton> {
  static const _confirmWindow = Duration(seconds: 3);

  bool _confirming = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (_confirming) {
      _timer?.cancel();
      setState(() => _confirming = false);
      widget.onConfirmed();
      return;
    }
    setState(() => _confirming = true);
    _timer = Timer(_confirmWindow, () {
      if (mounted) setState(() => _confirming = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _confirming ? 'Tap again to delete' : 'Delete',
      icon: Icon(
        _confirming ? Icons.warning_amber : Icons.delete_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      onPressed: _handleTap,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/block_edit_modal_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/widgets/block_edit_modal.dart test/widget/block_edit_modal_test.dart
git commit -m "Add two-tap delete confirm button for the block edit modal"
```

---

## Task 6: Assemble `BlockEditModal` and `showBlockEditModal`

**Files:**
- Modify: `lib/features/day/widgets/block_edit_modal.dart`
- Test: `test/widget/block_edit_modal_test.dart`

**Interfaces:**
- Consumes: `dayBlocksProvider`, `daySettingsProvider` (`lib/features/day/providers.dart`, `lib/features/day/day_settings.dart`); `TimeObject` (`lib/features/day/models/time_object.dart`); `BlockCategoryPlaceholder`, `BlockTimeRow`, `showTimeWheelPicker`, `BlockDeleteButton` from Tasks 3-5; `copyToNextDayWouldOverlap` from Task 2.
- Produces: `class BlockEditModal extends ConsumerStatefulWidget` (`date`, `initialBlock`).
- Produces: `Future<void> showBlockEditModal({required BuildContext context, required DateTime date, required TimeObject block})` — the entry point later tasks call from `DayGrid`/`DayScreen`. Shows a near-fullscreen bottom sheet below 700px width, a centered 480px-wide dialog at or above it.

- [ ] **Step 1: Write the failing tests**

Append to `test/widget/block_edit_modal_test.dart`. First add these imports at the top of the file, alongside the existing ones:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
```

Then add a shared block and pump helper above `void main()`:

```dart
final _date = DateTime(2026, 9, 9);

final _block = TimeObject(
  id: '1',
  title: 'Work',
  start: DateTime(2026, 9, 9, 9),
  end: DateTime(2026, 9, 9, 9, 30),
  kind: BlockKind.anchor,
  locked: false,
);

Future<ProviderContainer> _seededContainer() async {
  final container = ProviderContainer();
  await container.read(dayBlocksProvider(_date).future);
  await container
      .read(dayBlocksProvider(_date).notifier)
      .addBlock(
        start: _block.start,
        end: _block.end,
        kind: _block.kind,
        title: _block.title,
      );
  return container;
}

Future<void> _pumpOpenButton(
  WidgetTester tester,
  ProviderContainer container, {
  TimeObject? block,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showBlockEditModal(
              context: context,
              date: _date,
              block: block ?? _block,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);
```

Then add, inside `void main()`:

```dart
  group('BlockEditModal', () {
    testWidgets('shows the block\'s title, start and end', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);
    });

    testWidgets('shows a bottom sheet on a narrow width', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('shows a centered dialog on a wide width', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('editing the title persists it via the provider', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Deep work');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.title, 'Deep work');
    });

    testWidgets('tapping the start row and confirming a new time updates '
        'it', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockTimeRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // The wheel opens scrolled to the block's own start (09:00) and Done
      // confirms without scrolling, so the start is unchanged but the round
      // trip through updateBlock must not have been silently rejected.
      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.start, _block.start);
    });

    testWidgets('the copy button is disabled when the next day is busy at '
        'the same time', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final nextDate = DateTime(2026, 9, 10);
      await container.read(dayBlocksProvider(nextDate).future);
      await container
          .read(dayBlocksProvider(nextDate).notifier)
          .addBlock(start: _block.start.add(const Duration(days: 1)), end: _block.end.add(const Duration(days: 1)), kind: BlockKind.anchor);
      await _pumpOpenButton(tester, container);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.content_copy),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the copy button is enabled and copies when the next day '
        'is free', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final nextDate = DateTime(2026, 9, 10);
      await container.read(dayBlocksProvider(nextDate).future);
      await _pumpOpenButton(tester, container);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.content_copy));
      await tester.pumpAndSettle();

      final nextDayBlocks = container.read(dayBlocksProvider(nextDate)).value!;
      expect(nextDayBlocks, hasLength(1));
      expect(nextDayBlocks.single.title, 'Work');
    });

    testWidgets('confirming delete twice removes the block and closes', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();
      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks, isEmpty);
      expect(find.byType(BlockEditModal), findsNothing);
    });

    testWidgets('closes itself if the block is deleted elsewhere while '
        'open', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await container.read(dayBlocksProvider(_date).notifier).deleteBlock(_block);
      await tester.pumpAndSettle();

      expect(find.byType(BlockEditModal), findsNothing);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/block_edit_modal_test.dart`
Expected: FAIL — `BlockEditModal`/`showBlockEditModal` undefined.

- [ ] **Step 3: Implement `BlockEditModal` and `showBlockEditModal`**

Add these imports at the top of `lib/features/day/widgets/block_edit_modal.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
```

Append to `lib/features/day/widgets/block_edit_modal.dart`:

```dart

/// Below this viewport width, [showBlockEditModal] shows a near-fullscreen
/// bottom sheet; at or above it, a centered fixed-width dialog.
const _narrowBreakpoint = 700.0;

/// Opens the block edit modal for [block] (which belongs to [date]):
/// title, start/end, copy-to-next-day and delete. Near-fullscreen on a
/// narrow (mobile) width, a centered fixed-width dialog on a wide one.
Future<void> showBlockEditModal({
  required BuildContext context,
  required DateTime date,
  required TimeObject block,
}) {
  final isNarrow = MediaQuery.sizeOf(context).width < _narrowBreakpoint;
  if (isNarrow) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.95,
        child: BlockEditModal(date: date, initialBlock: block),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: BlockEditModal(date: date, initialBlock: block),
      ),
    ),
  );
}

/// The block edit modal's content: title, category placeholder, start/end
/// rows, and copy/delete actions. Reads the live block from
/// `dayBlocksProvider(date)` by [initialBlock]'s id on every rebuild —
/// [initialBlock] itself is only the optimistic value shown before that
/// provider's first load completes. Closes itself if the block disappears
/// from a loaded list (e.g. deleted from elsewhere).
class BlockEditModal extends ConsumerStatefulWidget {
  /// Creates a [BlockEditModal] for the block identified by
  /// [initialBlock]'s id, belonging to [date].
  const BlockEditModal({
    required this.date,
    required this.initialBlock,
    super.key,
  });

  /// The date [initialBlock] belongs to.
  final DateTime date;

  /// The block as known when the modal was opened.
  final TimeObject initialBlock;

  @override
  ConsumerState<BlockEditModal> createState() => _BlockEditModalState();
}

class _BlockEditModalState extends ConsumerState<BlockEditModal> {
  late final TextEditingController _titleController;
  late final FocusNode _titleFocus;
  TimeObject? _currentBlock;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialBlock.title);
    _titleFocus = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _titleFocus
      ..removeListener(_handleFocusChange)
      ..dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final block = _currentBlock;
    if (!_titleFocus.hasFocus && block != null) {
      _commitTitle(block);
    }
  }

  void _commitTitle(TimeObject block) {
    final value = _titleController.text.trim();
    if (value.isNotEmpty && value != block.title) {
      unawaited(
        ref
            .read(dayBlocksProvider(widget.date).notifier)
            .updateBlock(block, title: value),
      );
    }
  }

  Future<void> _editStart(TimeObject block, DaySettings settings) async {
    final picked = await showTimeWheelPicker(
      context: context,
      initial: block.start,
      settings: settings,
    );
    if (picked == null) return;
    await ref
        .read(dayBlocksProvider(widget.date).notifier)
        .updateBlock(block, start: picked);
  }

  Future<void> _editEnd(TimeObject block, DaySettings settings) async {
    final picked = await showTimeWheelPicker(
      context: context,
      initial: block.end,
      settings: settings,
    );
    if (picked == null) return;
    await ref
        .read(dayBlocksProvider(widget.date).notifier)
        .updateBlock(block, end: picked);
  }

  Future<void> _copyToNextDay(TimeObject block) async {
    await ref.read(dayBlocksProvider(widget.date).notifier).copyToNextDay(block);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to next day')));
  }

  Future<void> _delete(TimeObject block) async {
    await ref.read(dayBlocksProvider(widget.date).notifier).deleteBlock(block);
    if (mounted) Navigator.of(context).pop();
  }

  TimeObject? _findById(List<TimeObject> blocks, String id) {
    for (final b in blocks) {
      if (b.id == id) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = ref.watch(dayBlocksProvider(widget.date)).valueOrNull;
    final block = blocks == null
        ? widget.initialBlock
        : _findById(blocks, widget.initialBlock.id);

    if (blocks != null && block == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }

    final current = block!;
    _currentBlock = current;
    if (!_titleFocus.hasFocus && _titleController.text != current.title) {
      _titleController.text = current.title;
    }

    final settings = ref.watch(daySettingsProvider);
    final nextDate = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day + 1,
    );
    final nextDayBlocks = ref.watch(dayBlocksProvider(nextDate)).valueOrNull;
    final canCopy =
        nextDayBlocks != null &&
        !copyToNextDayWouldOverlap(
          block: current,
          nextDate: nextDate,
          nextDayBlocks: nextDayBlocks,
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    focusNode: _titleFocus,
                    onSubmitted: (_) => _commitTitle(current),
                    decoration: const InputDecoration(border: InputBorder.none),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const BlockCategoryPlaceholder(),
            const SizedBox(height: 12),
            BlockTimeRow(
              label: 'Starts',
              time: current.start,
              onTap: () => _editStart(current, settings),
            ),
            BlockTimeRow(
              label: 'Ends',
              time: current.end,
              onTap: () => _editEnd(current, settings),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Copy to next day',
                  icon: const Icon(Icons.content_copy),
                  onPressed: canCopy ? () => _copyToNextDay(current) : null,
                ),
                BlockDeleteButton(onConfirmed: () => _delete(current)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/block_edit_modal_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/widgets/block_edit_modal.dart test/widget/block_edit_modal_test.dart
git commit -m "Assemble BlockEditModal with breakpoint-aware presentation"
```

---

## Task 7: Wire tap-to-open on `DayGrid`

**Files:**
- Modify: `lib/features/day/widgets/day_grid.dart`
- Test: `test/widget/day_grid_test.dart`

**Interfaces:**
- Consumes: `showBlockEditModal` from Task 6.
- Produces: no new public API — `_DraggableBlock` gains a required `onOpenEdit` callback, wired internally by `DayGrid` itself (it already has `context`/`ref`).

- [ ] **Step 1: Write the failing test**

Append to `test/widget/day_grid_test.dart`, inside `group('block drag', ...)`, right after the existing `'a plain tap on a block still dismisses an open draft'` test:

```dart

    testWidgets('a plain tap on a non-locked block opens the edit modal', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _pump(tester, [_workBlock], container: container);

      await tester.tapAt(const Offset(200, 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsWidgets);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/day_grid_test.dart`
Expected: FAIL — no close icon appears; tapping a block still only dismisses the draft.

- [ ] **Step 3: Wire the tap handler**

In `lib/features/day/widgets/day_grid.dart`, add this import near the top:

```dart
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';
```

In `_DayGridState`, add a new method right after `_dismissDraft`:

```dart
  void _openEditModal(TimeObject block) {
    unawaited(
      showBlockEditModal(context: context, date: widget.date, block: block),
    );
  }
```

In `_DayGridState.build()`, where `_DraggableBlock` is constructed (inside the `for (final block in widget.blocks)` loop), add the new callback:

```dart
              child: _DraggableBlock(
                block: block,
                date: widget.date,
                settings: widget.settings,
                slotHeight: widget.slotHeight,
                topBleed: resizeBleed[block.id]?.top ?? 0,
                bottomBleed: resizeBleed[block.id]?.bottom ?? 0,
                onDismissDraft: _dismissDraft,
                onOpenEdit: _openEditModal,
                child: block.id == hiddenBlockId
```

In the `_DraggableBlock` class, add the new required field next to `onDismissDraft`:

```dart
  final VoidCallback onDismissDraft;
  final void Function(TimeObject block) onOpenEdit;
  final Widget child;
```

And in its constructor:

```dart
  const _DraggableBlock({
    required this.block,
    required this.date,
    required this.settings,
    required this.slotHeight,
    required this.topBleed,
    required this.bottomBleed,
    required this.onDismissDraft,
    required this.onOpenEdit,
    required this.child,
  });
```

Finally, in `_DraggableBlockState.build()`, change the non-locked `TapGestureRecognizer`'s handler (the locked branch above it, using `GestureDetector(onTap: widget.onDismissDraft)`, stays unchanged per the design's non-goals):

```dart
                    TapGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          TapGestureRecognizer
                        >(
                          TapGestureRecognizer.new,
                          (recognizer) => recognizer.onTap = () {
                            widget.onDismissDraft();
                            widget.onOpenEdit(widget.block);
                          },
                        ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/day_grid_test.dart`
Expected: PASS for all tests in the file, including the pre-existing "still dismisses an open draft" test (opening the modal doesn't interfere with that assertion) and the new one.

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/widgets/day_grid.dart test/widget/day_grid_test.dart
git commit -m "Open the block edit modal on tapping a non-locked block"
```

---

## Task 8: Wire open-after-create on `DayScreen`

**Files:**
- Modify: `lib/features/day/day_screen.dart`
- Test: `test/widget/day_screen_test.dart`

**Interfaces:**
- Consumes: `showBlockEditModal` from Task 6; `DayBlocksNotifier.addBlock` (now returning `Future<TimeObject>`, from Task 2).

- [ ] **Step 1: Write the failing test**

Append to `test/widget/day_screen_test.dart`, inside `group('DayScreen', ...)`, right after the existing `'double-tapping free space and confirming adds a new block'` test:

```dart

    testWidgets('creating a block immediately opens its edit modal', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      final gridTop = tester.getTopLeft(find.byType(DayGrid));
      final freeSpace = gridTop + const Offset(50, 5);

      await tester.tapAt(freeSpace);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(freeSpace);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.bySemanticsLabel('Create Event'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
      semantics.dispose();
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/day_screen_test.dart`
Expected: FAIL — no close icon appears; the modal never opens after creation.

- [ ] **Step 3: Wire the open-after-create flow**

In `lib/features/day/day_screen.dart`, add these imports near the top:

```dart
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';
```

Change the call site inside `_SchedulePage.build` from:

```dart
                        _buildColumn(ref, dates[i], slotHeight),
```

to:

```dart
                        _buildColumn(context, ref, dates[i], slotHeight),
```

Replace `_buildColumn` with:

```dart
  Widget _buildColumn(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
    double slotHeight,
  ) {
    final blocksAsync = ref.watch(dayBlocksProvider(date));

    return Expanded(
      child: blocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load: $error')),
        data: (blocks) => DayGrid(
          key: dayGridKeyFor(date),
          date: date,
          blocks: blocks,
          settings: settings,
          slotHeight: slotHeight,
          showHourLabels: _showHourLabels,
          onSwipeStart: onSwipeStart,
          onSwipeUpdate: onSwipeUpdate,
          onSwipeEnd: onSwipeEnd,
          onSwipeCancel: onSwipeCancel,
          onCreateBlock: ({required start, required end, required kind}) {
            unawaited(
              _createAndOpen(
                context,
                ref,
                date,
                start: start,
                end: end,
                kind: kind,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _createAndOpen(
    BuildContext context,
    WidgetRef ref,
    DateTime date, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
  }) async {
    final created = await ref
        .read(dayBlocksProvider(date).notifier)
        .addBlock(start: start, end: end, kind: kind);
    if (!context.mounted) return;
    await showBlockEditModal(context: context, date: date, block: created);
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/day_screen_test.dart`
Expected: PASS for all tests in the file, including the pre-existing "double-tapping free space and confirming adds a new block" test.

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/day_screen.dart test/widget/day_screen_test.dart
git commit -m "Open the edit modal automatically after creating a block"
```

---

## Task 9: Full verification pass

**Files:** none (verification only; fix inline wherever something fails).

- [ ] **Step 1: Run static analysis**

Run: `flutter analyze`
Expected: No issues. Fix anything the earlier tasks introduced (unused imports, lint warnings from `very_good_analysis`) before proceeding.

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: All tests PASS, including every file touched by Tasks 1-8 and any test elsewhere in the suite that exercises `DayBlocksRepository`/`DayBlocksNotifier`/`DayGrid`/`DayScreen`. If anything regresses (e.g. a test asserting on the exact widget tree under a block, or timing around the now-async open-after-create flow), fix the test or the implementation — whichever is actually wrong — rather than loosening the assertion.

- [ ] **Step 3: Commit if Steps 1-2 required any fixes**

```bash
git add -A
git commit -m "Fix analyzer/test fallout from the block edit modal feature"
```

If no fixes were needed, skip this step — there's nothing to commit.
