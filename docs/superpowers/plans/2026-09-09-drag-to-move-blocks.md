# Drag-to-Move Blocks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user pick up an existing timeline block (long-press on touch, click-and-drag on desktop) and move it — a 15-minute-snapped "landzone" shadow shows where it will land, the move can cross into another day/week (with edge-triggered auto-paging), and releasing commits the new date/time. No collision handling.

**Architecture:** A new ephemeral Riverpod `dragStateProvider` holds the in-flight drag (dragged block, origin date, current target date/time, last pointer position). Any mounted `DayGrid` column reads it to render the landzone shadow and hide the block being dragged from its origin column; `DayScreen` reads it to drive edge-triggered paging. Each non-locked block gets its own gesture recognizers (long-press for touch, immediate pan for mouse/trackpad) that write into the provider; a small resolver function finds which visible day column the pointer is currently over by looking up `GlobalObjectKey`-keyed `DayGrid` render boxes. Committing the move is a new `DayBlocksRepository.move` method.

**Tech Stack:** Flutter, `flutter_riverpod` (Notifier-based providers), `flutter_test` widget tests, Playwright e2e tests.

**Spec:** `docs/superpowers/specs/2026-09-09-drag-to-move-blocks-design.md`

## Global Constraints

- Landzone snaps to the 15-minute grid (reuse `slotStartForOffset` from `lib/features/day/day_new_block.dart`).
- Desktop (mouse/trackpad) drag starts immediately on pan, no hold delay; touch requires a long-press to start.
- `locked` blocks never respond to drag gestures (tap-to-dismiss-draft still works on them).
- No collision detection: a moved block may land overlapping any other block, or its own original spot.
- Dropping outside every visible day column cancels the move; the block stays where it was.
- Edge-zone width for auto-paging reuses the existing `_edgeFadeWidth` constant (72px) in `lib/features/day/day_screen.dart`; dwell time before paging is ~600ms, and continues paging one page at a time while held.

---

### Task 1: Repository `move` operation

**Files:**
- Modify: `lib/features/day/data/day_blocks_repository.dart`
- Test: `test/unit/day_blocks_repository_test.dart`

**Interfaces:**
- Produces: `Future<TimeObject> DayBlocksRepository.move(TimeObject block, {required DateTime fromDate, required DateTime toDate, required DateTime newStart, required DateTime newEnd})` — later tasks (3) call this via `ref.read(dayBlocksRepositoryProvider)`.

- [ ] **Step 1: Write the failing tests**

```dart
// Add to test/unit/day_blocks_repository_test.dart, inside the existing
// group('InMemoryDayBlocksRepository', () { ... }):

test('move updates an added block\'s start, end and date', () async {
  final date = DateTime.now().add(const Duration(days: 3));
  final laterDate = date.add(const Duration(days: 1));
  final added = await repository.add(
    date,
    start: DateTime(date.year, date.month, date.day, 10),
    end: DateTime(date.year, date.month, date.day, 10, 30),
    kind: BlockKind.anchor,
  );

  final moved = await repository.move(
    added,
    fromDate: date,
    toDate: laterDate,
    newStart: DateTime(laterDate.year, laterDate.month, laterDate.day, 14),
    newEnd: DateTime(laterDate.year, laterDate.month, laterDate.day, 14, 30),
  );

  expect(moved.id, added.id);
  expect(
    moved.start,
    DateTime(laterDate.year, laterDate.month, laterDate.day, 14),
  );
  expect(
    moved.end,
    DateTime(laterDate.year, laterDate.month, laterDate.day, 14, 30),
  );
});

test('move removes the block from its original date', () async {
  final date = DateTime.now().add(const Duration(days: 3));
  final laterDate = date.add(const Duration(days: 1));
  final added = await repository.add(
    date,
    start: DateTime(date.year, date.month, date.day, 10),
    end: DateTime(date.year, date.month, date.day, 10, 30),
    kind: BlockKind.anchor,
  );

  await repository.move(
    added,
    fromDate: date,
    toDate: laterDate,
    newStart: DateTime(laterDate.year, laterDate.month, laterDate.day, 14),
    newEnd: DateTime(laterDate.year, laterDate.month, laterDate.day, 14, 30),
  );

  expect(await repository.load(date), isEmpty);
});

test('move adds the block to its new date', () async {
  final date = DateTime.now().add(const Duration(days: 3));
  final laterDate = date.add(const Duration(days: 1));
  final added = await repository.add(
    date,
    start: DateTime(date.year, date.month, date.day, 10),
    end: DateTime(date.year, date.month, date.day, 10, 30),
    kind: BlockKind.anchor,
  );

  await repository.move(
    added,
    fromDate: date,
    toDate: laterDate,
    newStart: DateTime(laterDate.year, laterDate.month, laterDate.day, 14),
    newEnd: DateTime(laterDate.year, laterDate.month, laterDate.day, 14, 30),
  );

  final blocks = await repository.load(laterDate);
  expect(blocks, hasLength(1));
  expect(blocks.single.id, added.id);
});

test('moving a seeded block removes it from today and adds it to the '
    'new date', () async {
  final today = DateTime.now();
  final tomorrow = today.add(const Duration(days: 1));
  final seeded = (await repository.load(today))
      .firstWhere((b) => b.id == 'breakfast');

  await repository.move(
    seeded,
    fromDate: today,
    toDate: tomorrow,
    newStart: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8),
    newEnd: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8, 30),
  );

  final todayBlocks = await repository.load(today);
  expect(todayBlocks.where((b) => b.id == 'breakfast'), isEmpty);

  final tomorrowBlocks = await repository.load(tomorrow);
  expect(tomorrowBlocks.single.id, 'breakfast');
  expect(
    tomorrowBlocks.single.start,
    DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8),
  );
});

test('move within the same date just updates the block\'s time', () async {
  final date = DateTime.now().add(const Duration(days: 3));
  final added = await repository.add(
    date,
    start: DateTime(date.year, date.month, date.day, 10),
    end: DateTime(date.year, date.month, date.day, 10, 30),
    kind: BlockKind.anchor,
  );

  await repository.move(
    added,
    fromDate: date,
    toDate: date,
    newStart: DateTime(date.year, date.month, date.day, 15),
    newEnd: DateTime(date.year, date.month, date.day, 15, 30),
  );

  final blocks = await repository.load(date);
  expect(blocks, hasLength(1));
  expect(blocks.single.start, DateTime(date.year, date.month, date.day, 15));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/day_blocks_repository_test.dart`
Expected: FAIL — `move` is not defined on `DayBlocksRepository`/`InMemoryDayBlocksRepository`.

- [ ] **Step 3: Implement `move`**

In `lib/features/day/data/day_blocks_repository.dart`, add to the abstract
class (after `add`):

```dart
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
```

In `InMemoryDayBlocksRepository`, add a field to track seeded blocks that
have been moved (so `_seedFor` stops re-offering them under their original
date), and the `move` implementation:

```dart
  final Set<String> _movedSeedIds = {};

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
```

Update `load` to exclude moved-away seeded blocks — change `_seedFor`'s
return to filter them out:

```dart
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
      // ... existing seeded TimeObject list, unchanged ...
    ].where((block) => !_movedSeedIds.contains(block.id)).toList();
  }
```

(Only the `return [ ... ]` line changes — wrap the existing literal list
with `.where(...).toList()`; the list's contents stay exactly as they are
today.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/day_blocks_repository_test.dart`
Expected: PASS, including all existing tests in the file.

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/data/day_blocks_repository.dart test/unit/day_blocks_repository_test.dart
git commit -m "Add move operation to DayBlocksRepository"
```

---

### Task 2: `DragState` model

**Files:**
- Create: `lib/features/day/models/drag_state.dart`
- Test: `test/unit/drag_state_test.dart`

**Interfaces:**
- Consumes: `TimeObject` (`lib/features/day/models/time_object.dart`).
- Produces: `DragState` class with fields `block` (`TimeObject`),
  `originalDate` (`DateTime`), `targetDate` (`DateTime`), `targetStart`
  (`DateTime`), `pointerGlobalPosition` (`Offset`), and a `copyWith` method —
  used by Task 3's `DragNotifier`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/drag_state_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
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
  group('DragState', () {
    test('copyWith overrides only the given fields', () {
      final state = DragState(
        block: _block(),
        originalDate: DateTime(2026, 9, 9),
        targetDate: DateTime(2026, 9, 9),
        targetStart: DateTime(2026, 9, 9, 9),
        pointerGlobalPosition: const Offset(10, 20),
      );

      final updated = state.copyWith(
        targetDate: DateTime(2026, 9, 10),
        targetStart: DateTime(2026, 9, 10, 11),
        pointerGlobalPosition: const Offset(30, 40),
      );

      expect(updated.block, state.block);
      expect(updated.originalDate, state.originalDate);
      expect(updated.targetDate, DateTime(2026, 9, 10));
      expect(updated.targetStart, DateTime(2026, 9, 10, 11));
      expect(updated.pointerGlobalPosition, const Offset(30, 40));
    });

    test('copyWith with no arguments returns identical values', () {
      final state = DragState(
        block: _block(),
        originalDate: DateTime(2026, 9, 9),
        targetDate: DateTime(2026, 9, 9),
        targetStart: DateTime(2026, 9, 9, 9),
        pointerGlobalPosition: const Offset(10, 20),
      );

      final copy = state.copyWith();

      expect(copy.targetDate, state.targetDate);
      expect(copy.targetStart, state.targetStart);
      expect(copy.pointerGlobalPosition, state.pointerGlobalPosition);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/drag_state_test.dart`
Expected: FAIL — `package:taskframe/features/day/models/drag_state.dart` does not exist.

- [ ] **Step 3: Implement `DragState`**

```dart
// lib/features/day/models/drag_state.dart
import 'package:flutter/material.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// The in-flight state of a block being dragged to a new time/date.
///
/// `null` (held by `dragStateProvider`, not this class) means no drag is
/// in progress.
class DragState {
  /// Creates a [DragState].
  const DragState({
    required this.block,
    required this.originalDate,
    required this.targetDate,
    required this.targetStart,
    required this.pointerGlobalPosition,
  });

  /// The block being dragged, as it was before the drag started.
  final TimeObject block;

  /// The date [block] belonged to when the drag started.
  final DateTime originalDate;

  /// The date the landzone shadow is currently shown on.
  final DateTime targetDate;

  /// The 15-minute-grid-aligned time the landzone shadow currently starts
  /// at.
  final DateTime targetStart;

  /// The dragging pointer's last known position in global (screen)
  /// coordinates, used for edge-triggered day/week paging.
  final Offset pointerGlobalPosition;

  /// Returns a copy of this state with the given fields replaced.
  DragState copyWith({
    DateTime? targetDate,
    DateTime? targetStart,
    Offset? pointerGlobalPosition,
  }) {
    return DragState(
      block: block,
      originalDate: originalDate,
      targetDate: targetDate ?? this.targetDate,
      targetStart: targetStart ?? this.targetStart,
      pointerGlobalPosition:
          pointerGlobalPosition ?? this.pointerGlobalPosition,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/drag_state_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/models/drag_state.dart test/unit/drag_state_test.dart
git commit -m "Add DragState model"
```

---

### Task 3: `dragStateProvider` / `DragNotifier`

**Files:**
- Modify: `lib/features/day/providers.dart`
- Test: `test/unit/drag_state_provider_test.dart`

**Interfaces:**
- Consumes: `DragState` (Task 2), `TimeObject`, `dayBlocksRepositoryProvider`,
  `dayBlocksProvider` (both already in `providers.dart`),
  `DayBlocksRepository.move` (Task 1).
- Produces: `dragStateProvider` (`NotifierProvider<DragNotifier, DragState?>`)
  with methods `start({required TimeObject block, required DateTime
  originalDate, required Offset pointerGlobalPosition})`, `updatePointer(Offset
  globalPosition, {DateTime? targetDate, DateTime? targetStart})`, `Future<void>
  drop()`, `void cancel()` — used by Task 4 (rendering), Task 6 (gesture
  wiring), Task 7 (edge paging).

- [ ] **Step 1: Write the failing tests**

```dart
// test/unit/drag_state_provider_test.dart
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
```

Note: `addBlock` is declared `Future<void>` in `providers.dart` today (Task
3 does not change that) — the test above re-reads the block from state
after calling it rather than relying on `addBlock`'s own return value.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/drag_state_provider_test.dart`
Expected: FAIL — `dragStateProvider` is not defined.

- [ ] **Step 3: Implement `DragNotifier`/`dragStateProvider`**

Add to `lib/features/day/providers.dart` (new imports: `dart:ui` for
`Offset` — actually `flutter/material.dart` isn't imported here today, so
add `import 'package:flutter/widgets.dart';` for `Offset`; and `import
'package:taskframe/features/day/models/drag_state.dart';`):

```dart
/// Tracks the block currently being dragged to a new time/date, if any.
///
/// `null` when no drag is in progress. Read by any visible `DayGrid`
/// column to render the landzone shadow, and by `DayScreen` to drive
/// edge-triggered day/week paging.
class DragNotifier extends Notifier<DragState?> {
  @override
  DragState? build() => null;

  /// Begins dragging [block], which belonged to [originalDate]. The
  /// landzone starts at the block's own current date/time.
  void start({
    required TimeObject block,
    required DateTime originalDate,
    required Offset pointerGlobalPosition,
  }) {
    state = DragState(
      block: block,
      originalDate: originalDate,
      targetDate: originalDate,
      targetStart: block.start,
      pointerGlobalPosition: pointerGlobalPosition,
    );
  }

  /// Updates the dragging pointer's position. If [targetDate]/
  /// [targetStart] are given (the pointer is over a valid day column),
  /// the landzone moves there; otherwise only the pointer position
  /// updates, leaving the last valid landzone showing. Does nothing if no
  /// drag is in progress.
  void updatePointer(
    Offset globalPosition, {
    DateTime? targetDate,
    DateTime? targetStart,
  }) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      targetDate: targetDate,
      targetStart: targetStart,
      pointerGlobalPosition: globalPosition,
    );
  }

  /// Commits the current drag: moves the block to its current landzone
  /// date/time via the repository, refreshes both the origin and target
  /// day's blocks, then clears the drag. Does nothing if no drag is in
  /// progress.
  Future<void> drop() async {
    final current = state;
    if (current == null) return;
    state = null;

    final duration = current.block.end.difference(current.block.start);
    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.move(
      current.block,
      fromDate: current.originalDate,
      toDate: current.targetDate,
      newStart: current.targetStart,
      newEnd: current.targetStart.add(duration),
    );

    ref.invalidate(dayBlocksProvider(current.originalDate));
    ref.invalidate(dayBlocksProvider(current.targetDate));
  }

  /// Abandons the current drag without moving the block.
  void cancel() {
    state = null;
  }
}

/// The block currently being dragged to a new time/date, if any.
final dragStateProvider = NotifierProvider<DragNotifier, DragState?>(
  DragNotifier.new,
);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/drag_state_provider_test.dart`
Expected: PASS

Also run the full unit suite to confirm nothing else broke:
Run: `flutter test test/unit`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/providers.dart test/unit/drag_state_provider_test.dart
git commit -m "Add drag state provider for moving blocks"
```

---

### Task 4: `DayGrid` renders the landzone shadow and hides the dragged block

**Files:**
- Modify: `lib/features/day/widgets/day_grid.dart`
- Modify: `test/widget/day_grid_test.dart`

**Interfaces:**
- Consumes: `dragStateProvider`, `DragNotifier.start`/`updatePointer` (Task 3),
  `DragState` (Task 2).
- Produces: `DayGrid` becomes a `ConsumerStatefulWidget` (was
  `StatefulWidget`); the landzone shadow it renders carries `key: const
  Key('day-grid-landzone')` — used by this task's own tests and Task 6's.

- [ ] **Step 1: Update the test helper and write the failing tests**

`DayGrid` is about to require a Riverpod `ProviderScope` ancestor. Update
`test/widget/day_grid_test.dart`'s `_pump` helper to provide one, and add
landzone tests. Replace the whole file's top (imports and `_pump`) and add
a new `group('landzone', ...)`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);
const _slotHeight = 16.0;
final _date = DateTime(2026, 9, 9);

typedef _CreatedBlock = ({DateTime start, DateTime end, BlockKind kind});

Future<void> _pump(
  WidgetTester tester,
  List<TimeObject> blocks, {
  GestureDragStartCallback? onSwipeStart,
  GestureDragUpdateCallback? onSwipeUpdate,
  GestureDragEndCallback? onSwipeEnd,
  void Function({
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
  })?
  onCreateBlock,
  ProviderContainer? container,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container ?? ProviderContainer(),
    child: MaterialApp(
      home: Scaffold(
        body: DayGrid(
          date: _date,
          blocks: blocks,
          settings: _settings,
          slotHeight: _slotHeight,
          onSwipeStart: onSwipeStart,
          onSwipeUpdate: onSwipeUpdate,
          onSwipeEnd: onSwipeEnd,
          onCreateBlock:
              onCreateBlock ??
              ({required start, required end, required kind}) {},
        ),
      ),
    ),
  ),
);
```

(`container` defaults to a fresh, un-torn-down `ProviderContainer` per
pump — matching how existing tests never assert on provider disposal; a
container created this way is garbage-collected once the test ends. Every
other `testWidgets` body in the file is unchanged except this helper and
the two other `pumpWidget` call sites below, which need the same
`UncontrolledProviderScope` wrapper.)

Update the two other direct `tester.pumpWidget(MaterialApp(...))` call
sites in the file (`'uses whatever slotHeight it is given'` and
`'positions a block flush left when hour labels are hidden'`) to wrap
their `MaterialApp` in `UncontrolledProviderScope(container:
ProviderContainer(), child: ...)` the same way.

Add this new group at the end of `void main() { group('DayGrid', () {
... `, right before its closing `});`:

```dart
    group('landzone', () {
      testWidgets('does not show when no drag is in progress', (
        tester,
      ) async {
        await _pump(tester, [_workBlock]);

        expect(find.byKey(const Key('day-grid-landzone')), findsNothing);
      });

      testWidgets('shows at the drag target time when this grid is the '
          'target', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(dragStateProvider.notifier).start(
          block: _workBlock,
          originalDate: _date,
          pointerGlobalPosition: const Offset(0, 0),
        );
        container.read(dragStateProvider.notifier).updatePointer(
          const Offset(0, 0),
          targetDate: _date,
          targetStart: DateTime(2026, 9, 9, 11),
        );

        await _pump(tester, [_workBlock], container: container);

        final landzone = tester.widget<Positioned>(
          find.ancestor(
            of: find.byKey(const Key('day-grid-landzone')),
            matching: find.byType(Positioned),
          ),
        );
        // 11:00 is 5 hours (20 slots) after the 6:00 day start.
        expect(landzone.top, 20 * _slotHeight);
        // Work is a 4-hour block, unchanged by the move.
        expect(landzone.height, 16 * _slotHeight);
      });

      testWidgets('does not show when this grid is not the drag target', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(dragStateProvider.notifier).start(
          block: _workBlock,
          originalDate: _date,
          pointerGlobalPosition: const Offset(0, 0),
        );
        container.read(dragStateProvider.notifier).updatePointer(
          const Offset(0, 0),
          targetDate: DateTime(2026, 9, 10),
          targetStart: DateTime(2026, 9, 10, 11),
        );

        await _pump(tester, [_workBlock], container: container);

        expect(find.byKey(const Key('day-grid-landzone')), findsNothing);
      });

      testWidgets('hides the real block in its origin column while '
          'dragging', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(dragStateProvider.notifier).start(
          block: _workBlock,
          originalDate: _date,
          pointerGlobalPosition: const Offset(0, 0),
        );

        await _pump(tester, [_workBlock], container: container);

        expect(find.text('Work'), findsNothing);
      });
    });
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `flutter test test/widget/day_grid_test.dart`
Expected: FAIL — landzone tests fail (`dragStateProvider` renders nothing
yet); the updated `_pump`-based tests still pass since `UncontrolledProviderScope`
is a no-op ancestor for a plain `StatefulWidget`.

- [ ] **Step 3: Implement landzone rendering in `DayGrid`**

In `lib/features/day/widgets/day_grid.dart`:

Add imports:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/providers.dart';
```

Change the class declarations:
```dart
class DayGrid extends ConsumerStatefulWidget {
  // ...unchanged constructor/fields...

  @override
  ConsumerState<DayGrid> createState() => _DayGridState();
}

class _DayGridState extends ConsumerState<DayGrid> {
```

(`initState`/`didUpdateWidget`/`dispose`/helper getters stay exactly as
they are — `ConsumerState` is a drop-in `State` subclass.)

In `build()`, right after `final draft = _draft;` add:

```dart
    final dragState = ref.watch(dragStateProvider);
    final hiddenBlockId =
        dragState != null && dragState.originalDate == widget.date
        ? dragState.block.id
        : null;
    final landzone = dragState != null && dragState.targetDate == widget.date
        ? dragState
        : null;
```

Change the block-rendering loop to skip the hidden block:
```dart
          for (final block in widget.blocks)
            if (block.id != hiddenBlockId)
              Positioned(
                top: _offsetFor(block.start),
                left: _gridLeft,
                right: 0,
                height: _offsetFor(block.end) - _offsetFor(block.start),
                child: Container(
                  color: scheme.surface,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: BlockView(block: block),
                ),
              ),
```

Add the landzone rendering after the draft `Positioned` block (before the
now-line):
```dart
          if (landzone != null)
            Positioned(
              key: const Key('day-grid-landzone'),
              top: _offsetFor(landzone.targetStart),
              left: _gridLeft,
              right: 0,
              height:
                  _offsetFor(
                    landzone.targetStart.add(
                      landzone.block.end.difference(landzone.block.start),
                    ),
                  ) -
                  _offsetFor(landzone.targetStart),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.15),
                    border: Border.all(color: scheme.primary),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/day_grid_test.dart`
Expected: PASS

Run: `flutter test test/widget test/unit`
Expected: PASS (confirms `day_screen_test.dart`, which pumps `DayGrid`
indirectly inside its own `ProviderScope`/`UncontrolledProviderScope`
already, is unaffected).

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/widgets/day_grid.dart test/widget/day_grid_test.dart
git commit -m "Render the landzone shadow and hide the dragged block in DayGrid"
```

---

### Task 5: Column resolution (`resolveDragTarget`) and `pageDates` wiring

**Files:**
- Create: `lib/features/day/widgets/drag_target_resolver.dart`
- Modify: `lib/features/day/widgets/day_grid.dart`
- Modify: `lib/features/day/day_screen.dart`
- Test: `test/widget/drag_target_resolver_test.dart`

**Interfaces:**
- Consumes: `slotStartForOffset` (`lib/features/day/day_new_block.dart`),
  `DaySettings`.
- Produces: `GlobalKey dayGridKeyFor(DateTime date)` and `({DateTime date,
  DateTime start})? resolveDragTarget({required Offset globalPosition,
  required List<DateTime> pageDates, required DaySettings settings, required
  double slotHeight})` — used by Task 6. `DayGrid` gains an optional
  `List<DateTime>? pageDates` constructor parameter (defaults to `[date]`)
  and is now given `key: dayGridKeyFor(date)` wherever `_SchedulePage`
  builds it.

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/drag_target_resolver_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);
const _slotHeight = 16.0;
final _dates = [DateTime(2026, 9, 9), DateTime(2026, 9, 10)];

Future<void> _pumpTwoColumns(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          for (final date in _dates)
            SizedBox(
              key: dayGridKeyFor(date),
              width: 300,
              height: 1088, // 68 slots * 16.
            ),
        ],
      ),
    ),
  ),
);

void main() {
  group('resolveDragTarget', () {
    testWidgets('finds the column and snapped time under the position', (
      tester,
    ) async {
      await _pumpTwoColumns(tester);
      // Second column starts at x=300; y=192 is 3 hours (12 slots) past
      // the 6:00 day start.
      final target = resolveDragTarget(
        globalPosition: const Offset(310, 192),
        pageDates: _dates,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(target?.date, _dates[1]);
      expect(target?.start, DateTime(2026, 9, 10, 9));
    });

    testWidgets('returns null when the position is over no known column', (
      tester,
    ) async {
      await _pumpTwoColumns(tester);

      final target = resolveDragTarget(
        globalPosition: const Offset(3000, 192),
        pageDates: _dates,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(target, isNull);
    });

    testWidgets('returns null when the position is below the grid', (
      tester,
    ) async {
      await _pumpTwoColumns(tester);

      final target = resolveDragTarget(
        globalPosition: const Offset(10, 5000),
        pageDates: _dates,
        settings: _settings,
        slotHeight: _slotHeight,
      );

      expect(target, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/drag_target_resolver_test.dart`
Expected: FAIL — `drag_target_resolver.dart` does not exist.

- [ ] **Step 3: Implement `resolveDragTarget`**

```dart
// lib/features/day/widgets/drag_target_resolver.dart
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';

/// The stable [GlobalKey] a `DayGrid` for [date] is built with, so
/// [resolveDragTarget] can find its render box regardless of which page
/// or column a drag started in.
GlobalKey dayGridKeyFor(DateTime date) => GlobalObjectKey(date);

/// Finds which of [pageDates]' day columns [globalPosition] currently
/// falls over, and the 15-minute slot within it, by looking up each
/// date's mounted widget via [dayGridKeyFor].
///
/// Returns `null` if [globalPosition] isn't over any of [pageDates]'
/// columns.
({DateTime date, DateTime start})? resolveDragTarget({
  required Offset globalPosition,
  required List<DateTime> pageDates,
  required DaySettings settings,
  required double slotHeight,
}) {
  for (final date in pageDates) {
    final renderObject = dayGridKeyFor(
      date,
    ).currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) continue;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    if (!rect.contains(globalPosition)) continue;

    final start = slotStartForOffset(
      day: date,
      dy: globalPosition.dy - topLeft.dy,
      settings: settings,
      slotHeight: slotHeight,
    );
    if (start == null) continue;

    return (date: date, start: start);
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/drag_target_resolver_test.dart`
Expected: PASS

- [ ] **Step 5: Wire `pageDates` into `DayGrid` and key it in `_SchedulePage`**

In `lib/features/day/widgets/day_grid.dart`, add to `DayGrid`'s
constructor parameters (alongside `showHourLabels`):
```dart
    this.pageDates,
```
and the field:
```dart
  /// Every date visible on the current page (the single [date] outside
  /// week view, or all 7 dates in week view), used to resolve which
  /// column a drag's pointer currently falls over. Defaults to `[date]`
  /// when not given.
  final List<DateTime>? pageDates;
```
and a getter in `_DayGridState`:
```dart
  List<DateTime> get _pageDates => widget.pageDates ?? [widget.date];
```
(not used yet — Task 6 reads it).

In `lib/features/day/day_screen.dart`, import the resolver:
```dart
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
```
In `_SchedulePage._buildColumn`, pass `key` and `pageDates` to `DayGrid`:
```dart
  Widget _buildColumn(WidgetRef ref, DateTime date, double slotHeight) {
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
          pageDates: List.generate(
            dayCount,
            (i) => DateTime(startDate.year, startDate.month, startDate.day + i),
          ),
          onSwipeStart: onSwipeStart,
          onSwipeUpdate: onSwipeUpdate,
          onSwipeEnd: onSwipeEnd,
          onSwipeCancel: onSwipeCancel,
          onCreateBlock: ({required start, required end, required kind}) {
            unawaited(
              ref
                  .read(dayBlocksProvider(date).notifier)
                  .addBlock(start: start, end: end, kind: kind),
            );
          },
        ),
      ),
    );
  }
```

- [ ] **Step 6: Run the full widget suite to verify nothing broke**

Run: `flutter test test/widget test/unit`
Expected: PASS — `key: dayGridKeyFor(date)` is a stable, per-date
`GlobalObjectKey`, so existing `DayScreen`/`DayGrid` tests (which never
assert on widget identity across rebuilds) are unaffected.

- [ ] **Step 7: Commit**

```bash
git add lib/features/day/widgets/drag_target_resolver.dart lib/features/day/widgets/day_grid.dart lib/features/day/day_screen.dart test/widget/drag_target_resolver_test.dart
git commit -m "Add drag target column resolution and page-date wiring"
```

---

### Task 6: Per-block drag gestures

**Files:**
- Modify: `lib/features/day/widgets/day_grid.dart`
- Modify: `test/widget/day_grid_test.dart`

**Interfaces:**
- Consumes: `dragStateProvider` (Task 3), `resolveDragTarget`/`dayGridKeyFor`
  (Task 5), `widget.pageDates` (Task 5).
- Produces: non-locked blocks respond to long-press-drag (touch) and
  immediate pan-drag (mouse/trackpad); locked blocks only respond to tap
  (dismisses an open draft, same as before this task).

- [ ] **Step 1: Write the failing tests**

Add to `test/widget/day_grid_test.dart`, a new top-level helper and group
(the file already imports `flutter/gestures.dart` and
`flutter_riverpod/flutter_riverpod.dart` from Task 4's edit):

```dart
/// Starts a touch drag on [block] within a single-column [_pump]ed grid,
/// waiting out the long-press timeout before the first move so the
/// gesture arena has resolved in favor of the long-press recognizer.
Future<TestGesture> _startTouchDrag(
  WidgetTester tester,
  Offset position,
) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.touch,
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return gesture;
}
```

```dart
    group('block drag', () {
      testWidgets('a mouse drag on a block starts immediately, no hold '
          'needed', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        // 300 is inside Work's y range (192-448).
        final gesture = await tester.startGesture(
          const Offset(200, 300),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();

        expect(container.read(dragStateProvider), isNotNull);
        await gesture.up();
      });

      testWidgets('a touch drag on a block requires a long-press to start', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        final gesture = await tester.startGesture(
          const Offset(200, 300),
          kind: PointerDeviceKind.touch,
        );
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();

        // No long-press timeout elapsed yet: no drag started.
        expect(container.read(dragStateProvider), isNull);

        await gesture.up();
      });

      testWidgets('a long-press-and-move on a block starts a drag on '
          'touch', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        final gesture = await _startTouchDrag(
          tester,
          const Offset(200, 300),
        );
        await gesture.moveBy(const Offset(0, 32));
        await tester.pump();

        expect(container.read(dragStateProvider), isNotNull);
        await gesture.up();
      });

      testWidgets('releasing a drag over a valid slot commits the move', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [_workBlock], container: container);

        final gesture = await _startTouchDrag(
          tester,
          const Offset(200, 300),
        );
        // Move down by 32px = 2 slots = 30 minutes.
        await gesture.moveBy(const Offset(0, 32));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        expect(container.read(dragStateProvider), isNull);
      });

      testWidgets('a locked block ignores drag gestures', (tester) async {
        final locked = TimeObject(
          id: '1',
          title: 'Locked',
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 13),
          kind: BlockKind.frame,
          locked: true,
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _pump(tester, [locked], container: container);

        final gesture = await tester.startGesture(
          const Offset(200, 300),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();

        expect(container.read(dragStateProvider), isNull);
        await gesture.up();
      });

      testWidgets('a plain tap on a block still dismisses an open draft', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, [_workBlock]);
        await _doubleTapAt(tester, const Offset(200, 500));
        expect(find.bySemanticsLabel('Create Event'), findsOneWidget);

        await tester.tapAt(const Offset(200, 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.bySemanticsLabel('Create Event'), findsNothing);
        semantics.dispose();
      });
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/day_grid_test.dart`
Expected: FAIL — no gesture handling wired to blocks yet, so
`dragStateProvider` never changes and the draft-dismiss-via-block-tap test
still passes today only because plain taps fall through to the grid (that
one may already pass; the drag-related ones fail).

- [ ] **Step 3: Implement per-block gesture wiring**

Add imports to `lib/features/day/widgets/day_grid.dart`:
```dart
import 'package:flutter/gestures.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
```

Add a new private widget after `_DayGridState` (or anywhere top-level in
the file):

```dart
/// Wraps one rendered block with its drag gestures: a long-press-and-move
/// on touch, an immediate pan on mouse/trackpad, and a plain tap
/// (forwarded to [onDismissDraft]) on any device. Locked blocks only get
/// the tap handler.
class _DraggableBlock extends ConsumerWidget {
  const _DraggableBlock({
    required this.block,
    required this.date,
    required this.pageDates,
    required this.settings,
    required this.slotHeight,
    required this.onDismissDraft,
    required this.child,
  });

  final TimeObject block;
  final DateTime date;
  final List<DateTime> pageDates;
  final DaySettings settings;
  final double slotHeight;
  final VoidCallback onDismissDraft;
  final Widget child;

  void _start(WidgetRef ref, Offset globalPosition) {
    ref
        .read(dragStateProvider.notifier)
        .start(
          block: block,
          originalDate: date,
          pointerGlobalPosition: globalPosition,
        );
  }

  void _update(WidgetRef ref, Offset globalPosition) {
    final target = resolveDragTarget(
      globalPosition: globalPosition,
      pageDates: pageDates,
      settings: settings,
      slotHeight: slotHeight,
    );
    ref
        .read(dragStateProvider.notifier)
        .updatePointer(
          globalPosition,
          targetDate: target?.date,
          targetStart: target?.start,
        );
  }

  void _end(WidgetRef ref, Offset globalPosition) {
    final notifier = ref.read(dragStateProvider.notifier);
    final target = resolveDragTarget(
      globalPosition: globalPosition,
      pageDates: pageDates,
      settings: settings,
      slotHeight: slotHeight,
    );
    if (target == null) {
      notifier.cancel();
    } else {
      unawaited(notifier.drop());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (block.locked) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismissDraft,
        child: child,
      );
    }

    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (recognizer) => recognizer.onTap = onDismissDraft,
            ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer()
                ..supportedDevices = {PointerDeviceKind.touch},
              (recognizer) => recognizer
                ..onLongPressStart = (details) =>
                    _start(ref, details.globalPosition)
                ..onLongPressMoveUpdate = (details) =>
                    _update(ref, details.globalPosition)
                ..onLongPressEnd = (details) =>
                    _end(ref, details.globalPosition)
                ..onLongPressCancel = () =>
                    ref.read(dragStateProvider.notifier).cancel(),
            ),
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer()
                ..supportedDevices = {
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              (recognizer) => recognizer
                ..onStart = (details) => _start(ref, details.globalPosition)
                ..onUpdate = (details) => _update(ref, details.globalPosition)
                ..onEnd = (_) {
                  final position = ref
                      .read(dragStateProvider)
                      ?.pointerGlobalPosition;
                  if (position != null) _end(ref, position);
                }
                ..onCancel = () =>
                    ref.read(dragStateProvider.notifier).cancel(),
            ),
      },
      child: child,
    );
  }
}
```

Update the block-rendering loop in `_DayGridState.build()` to wrap each
block:
```dart
          for (final block in widget.blocks)
            if (block.id != hiddenBlockId)
              Positioned(
                top: _offsetFor(block.start),
                left: _gridLeft,
                right: 0,
                height: _offsetFor(block.end) - _offsetFor(block.start),
                child: _DraggableBlock(
                  block: block,
                  date: widget.date,
                  pageDates: _pageDates,
                  settings: widget.settings,
                  slotHeight: widget.slotHeight,
                  onDismissDraft: _dismissDraft,
                  child: Container(
                    color: scheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: BlockView(block: block),
                  ),
                ),
              ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/day_grid_test.dart`
Expected: PASS

Run: `flutter test test/widget test/unit`
Expected: PASS — confirms the existing `'a fling starting on a block is
not forwarded'` test (which flings starting mid-block) still passes: a
`PanGestureRecognizer` restricted to mouse/trackpad now also competes for
that pointer, but `flingFrom` in that test uses the default touch pointer
kind, so only the grid's own `onHorizontalDragStart` (unaffected by this
task) and the block's `LongPressGestureRecognizer` (which a fling's short
duration never satisfies) are in play — the swipe-forwarding behavior is
untouched.

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/widgets/day_grid.dart test/widget/day_grid_test.dart
git commit -m "Wire per-block drag gestures for moving blocks"
```

---

### Task 7: Edge-triggered day/week paging during a drag

**Files:**
- Modify: `lib/features/day/day_screen.dart`
- Modify: `test/widget/day_screen_test.dart`

**Interfaces:**
- Consumes: `dragStateProvider`, `DragState.pointerGlobalPosition` (Task 3),
  `_animateBy` (already in `_DayScreenState`), `_edgeFadeWidth` (already
  defined in `day_screen.dart`).
- Produces: no new public interface — purely wires existing paging to the
  drag state.

- [ ] **Step 1: Write the failing tests**

Add to `test/widget/day_screen_test.dart`, a new group (the file already
imports what's needed; add `import 'package:taskframe/features/day/models/drag_state.dart';`
and `import 'package:taskframe/features/day/models/time_object.dart';`):

```dart
  group('edge-triggered paging during a drag', () {
    testWidgets('dwelling in the left edge zone pages to the previous day', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DayScreen()),
        ),
      );
      await tester.pump();

      final block = TimeObject(
        id: 'dragged',
        title: 'Breakfast',
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(minutes: 30)),
        kind: BlockKind.anchor,
        locked: false,
      );
      container.read(dragStateProvider.notifier).start(
        block: block,
        originalDate: container.read(selectedDateProvider),
        pointerGlobalPosition: const Offset(500, 500),
      );

      container
          .read(dragStateProvider.notifier)
          .updatePointer(const Offset(10, 500));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();

      expect(find.text('Breakfast'), findsNothing);
    });

    testWidgets('leaving the edge zone before the dwell time cancels the '
        'page turn', (tester) async {
      _resizeViewport(tester, const Size(800, 1000));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DayScreen()),
        ),
      );
      await tester.pump();

      final block = TimeObject(
        id: 'dragged',
        title: 'Breakfast',
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(minutes: 30)),
        kind: BlockKind.anchor,
        locked: false,
      );
      container.read(dragStateProvider.notifier).start(
        block: block,
        originalDate: container.read(selectedDateProvider),
        pointerGlobalPosition: const Offset(500, 500),
      );

      container
          .read(dragStateProvider.notifier)
          .updatePointer(const Offset(10, 500));
      await tester.pump(const Duration(milliseconds: 300));
      container
          .read(dragStateProvider.notifier)
          .updatePointer(const Offset(400, 500));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();

      expect(find.text('Breakfast'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/day_screen_test.dart`
Expected: FAIL — no edge-dwell behavior wired yet.

- [ ] **Step 3: Implement edge-dwell paging**

In `lib/features/day/day_screen.dart`, add near the other top-level
constants:
```dart
/// How long the drag pointer must stay in an edge zone before it pages to
/// the adjacent day/week.
const _edgeDwellDuration = Duration(milliseconds: 600);
```

Add fields to `_DayScreenState` (alongside `Drag? _drag;`):
```dart
  Timer? _edgeDwellTimer;
  int? _edgeDwellDirection;
```

Add methods:
```dart
  void _handleDragPointer(DragState? drag) {
    if (drag == null) {
      _cancelEdgeDwell();
      return;
    }

    final width = MediaQuery.sizeOf(context).width;
    final dx = drag.pointerGlobalPosition.dx;
    int? direction;
    if (dx <= _edgeFadeWidth) {
      direction = -1;
    } else if (dx >= width - _edgeFadeWidth) {
      direction = 1;
    }

    if (direction == null) {
      _cancelEdgeDwell();
      return;
    }
    if (_edgeDwellDirection == direction) return;

    _cancelEdgeDwell();
    _edgeDwellDirection = direction;
    _edgeDwellTimer = Timer(_edgeDwellDuration, () {
      final pagedDirection = direction!;
      _edgeDwellTimer = null;
      _edgeDwellDirection = null;
      unawaited(_animateBy(pagedDirection));
      _handleDragPointer(ref.read(dragStateProvider));
    });
  }

  void _cancelEdgeDwell() {
    _edgeDwellTimer?.cancel();
    _edgeDwellTimer = null;
    _edgeDwellDirection = null;
  }
```

Update `dispose()`:
```dart
  @override
  void dispose() {
    _cancelEdgeDwell();
    _pageController.dispose();
    super.dispose();
  }
```

In `build()`, right after `final daysPerPage = _daysPerPage!;` add:
```dart
    ref.listen<DragState?>(dragStateProvider, (_, next) {
      _handleDragPointer(next);
    });
```

Add the required import:
```dart
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/providers.dart' show dragStateProvider;
```
(`providers.dart` is likely already imported for `daySettingsProvider`/
`dayBlocksProvider`/`selectedDateProvider` — if so, just add
`dragStateProvider` to that existing import's shown names, or drop the
`show` clause entirely and rely on the existing unqualified import.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/day_screen_test.dart`
Expected: PASS

Run: `flutter test`
Expected: PASS (full suite).

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/day_screen.dart test/widget/day_screen_test.dart
git commit -m "Add edge-triggered day/week paging while dragging a block"
```

---

### Task 8: E2E coverage for cross-day drag

**Files:**
- Create: `e2e/tests/day-drag-event.spec.ts`
- Modify: `e2e/tests/support/gestures.ts`

**Interfaces:**
- Consumes: `enableFlutterAccessibility` (`e2e/tests/support/accessibility.ts`,
  existing).
- Produces: `dragMouse(page, from, to, { steps }): Promise<void>` helper in
  `gestures.ts`, used by the new spec.

- [ ] **Step 1: Add the drag helper**

Add to `e2e/tests/support/gestures.ts`:
```typescript
/**
 * Drags the mouse from [from] to [to] in [steps] intermediate moves,
 * holding the button down for the whole path and releasing at [to].
 * Used to simulate a desktop block drag, which starts immediately on
 * mouse-down (no long-press needed).
 */
export async function dragMouse(
  page: Page,
  from: { x: number; y: number },
  to: { x: number; y: number },
  { steps = 10 }: { steps?: number } = {},
): Promise<void> {
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  for (let i = 1; i <= steps; i++) {
    const x = from.x + ((to.x - from.x) * i) / steps;
    const y = from.y + ((to.y - from.y) * i) / steps;
    await page.mouse.move(x, y);
  }
  await page.mouse.up();
}
```

- [ ] **Step 2: Write the e2e test**

```typescript
// e2e/tests/day-drag-event.spec.ts
import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { dragMouse } from './support/gestures';

test.use({ viewport: { width: 800, height: 720 } });

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached' });
  await enableFlutterAccessibility(page);
});

test('dragging a block to a new time moves it there', async ({ page }) => {
  // Breakfast is at 7:00-7:30, a fixed hardcoded block for today.
  await expect(page.getByText('Breakfast')).toBeVisible();
  const breakfast = page.getByText('Breakfast');
  const box = (await breakfast.boundingBox())!;

  // Drag straight down by roughly 4 hours' worth of pixels; the exact
  // landing slot isn't asserted, only that the block moved off its
  // original position.
  await dragMouse(
    page,
    { x: box.x + box.width / 2, y: box.y + box.height / 2 },
    { x: box.x + box.width / 2, y: box.y + box.height / 2 + 300 },
  );

  await expect(page.getByText('Breakfast')).toBeVisible();
  const movedBox = (await page.getByText('Breakfast').boundingBox())!;
  expect(movedBox.y).toBeGreaterThan(box.y + 50);
});

test('dragging a block into the right edge pages to the next day', async ({
  page,
}) => {
  await expect(page.getByText('Breakfast')).toBeVisible();
  const breakfast = page.getByText('Breakfast');
  const box = (await breakfast.boundingBox())!;

  // Drag to the right edge and hold there past the dwell time before
  // releasing, so the screen pages to tomorrow.
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(780, box.y + box.height / 2);
  await page.waitForTimeout(700);
  await page.mouse.move(780, box.y + box.height / 2 + 1);
  await page.mouse.up();

  await expect(page.getByText('Breakfast')).toHaveCount(0);
});
```

- [ ] **Step 3: Run the e2e suite**

Run: `cd e2e && npx playwright test day-drag-event.spec.ts`
Expected: PASS (both tests). If the drag distance/edge coordinates need
tuning for the real rendered slot height at 800x720, adjust the pixel
offsets used above rather than the app code.

- [ ] **Step 4: Commit**

```bash
git add e2e/tests/day-drag-event.spec.ts e2e/tests/support/gestures.ts
git commit -m "Add e2e coverage for dragging blocks across times and days"
```
