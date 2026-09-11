# Event templates (stage 1: template editor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/templates` screen where named templates (reusable sets of events) can be created, removed, and edited with the same schedule UI (add/edit/delete/drag/resize blocks) the Day screen already has — without duplicating that UI's gesture-handling code.

**Architecture:** Split "which column a block lives in" (a `ScheduleColumn`: a calendar day or a template id) from "what time of day it occupies" (still `DateTime`, read only for hour/minute). Generalize the day feature's shared grid/drag/resize/edit-modal code to work over `ScheduleColumn`, with feature-specific data access injected by the caller (`DayScreen` vs a new `TemplatesScreen`) through two small strategy interfaces — a `Ref`-based `ScheduleController` for drag/resize, a `WidgetRef`-based `ScheduleBlockActions` for the edit modal — so `lib/features/day/` never imports the new `lib/features/template/`.

**Tech Stack:** Flutter, `flutter_riverpod` 3.4.3 (`Notifier`/`AsyncNotifier`/`.family`), `go_router` 18.0.1, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-11-event-templates-design.md`

## Global Constraints

- Every existing test in `test/unit/` and `test/widget/` must keep passing after each task that touches shared code — run the full suite (`flutter test`), not just the new/changed test file, before that task's commit.
- No new adaptive-layout package; reuse `lib/core/responsive.dart`'s `isNarrow`.
- In-memory storage only (mirrors `InMemoryDayBlocksRepository`) — no persistence backend.
- `lib/features/day/` must never import anything from `lib/features/template/`.

---

## File Structure

New files:
- `lib/features/day/models/schedule_column.dart` — `ScheduleColumn`/`DayColumn`/`TemplateColumn`, `anchorDateFor`.
- `lib/features/day/schedule_controller.dart` — `ScheduleController` abstract class (`Ref`-based).
- `lib/features/day/day_schedule_controller.dart` — `DayScheduleController`.
- `lib/features/day/widgets/schedule_block_actions.dart` — `ScheduleBlockActions` (`WidgetRef`-based).
- `lib/features/day/day_schedule_block_actions.dart` — `dayScheduleBlockActions` constant.
- `lib/features/template/models/template.dart` — `Template`.
- `lib/features/template/data/template_repository.dart` — `TemplateRepository`/`InMemoryTemplateRepository`, `TemplateBlocksRepository`/`InMemoryTemplateBlocksRepository`.
- `lib/features/template/providers.dart` — `templateListProvider`, `templateBlocksProvider`, `TemplateScheduleController`, `templateScheduleBlockActions`.
- `lib/features/template/widgets/templates_screen.dart` — `TemplatesScreen`.

Modified files:
- `lib/features/day/models/drag_state.dart`, `models/resize_state.dart` — `DateTime` → `ScheduleColumn` fields.
- `lib/features/day/widgets/drag_target_resolver.dart` — `dayGridKeyFor` → `scheduleGridKeyFor`, `resolveDragTarget` over `ScheduleColumn`.
- `lib/features/day/providers.dart` — `DragNotifier`/`ResizeNotifier` generalized.
- `lib/features/day/widgets/day_grid.dart` — `DayGrid`/`_DraggableBlock` take `column`/`controller`.
- `lib/features/day/widgets/block_edit_modal.dart` — `BlockEditModal`/`showBlockEditModal` take `column`/`actions`.
- `lib/features/day/day_screen.dart` — constructs `DayColumn`/`DayScheduleController`/`dayScheduleBlockActions`.
- `lib/router.dart`, `lib/core/widgets/app_shell.dart` — add `/templates` branch/destination.
- Matching test files for every file above (listed per task).

---

### Task 1: `ScheduleColumn` model

**Files:**
- Create: `lib/features/day/models/schedule_column.dart`
- Test: `test/unit/schedule_column_test.dart`

**Interfaces:**
- Produces: `sealed class ScheduleColumn`, `class DayColumn extends ScheduleColumn { const DayColumn(DateTime date); final DateTime date; }`, `class TemplateColumn extends ScheduleColumn { const TemplateColumn(String templateId); final String templateId; }`, `DateTime anchorDateFor(ScheduleColumn column)`, `final DateTime templateAnchorDate`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/schedule_column_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';

void main() {
  group('DayColumn', () {
    test('equal when the calendar day matches, ignoring time of day', () {
      expect(
        const DayColumn.internal(DateTime(2026, 9, 9, 10, 30)),
        const DayColumn.internal(DateTime(2026, 9, 9, 22)),
      );
    });

    test('not equal on a different calendar day', () {
      expect(
        const DayColumn.internal(DateTime(2026, 9, 9)) ==
            const DayColumn.internal(DateTime(2026, 9, 10)),
        isFalse,
      );
    });

    test('hashCode matches for the same calendar day', () {
      expect(
        const DayColumn.internal(DateTime(2026, 9, 9, 10, 30)).hashCode,
        const DayColumn.internal(DateTime(2026, 9, 9, 22)).hashCode,
      );
    });
  });

  group('TemplateColumn', () {
    test('equal when the templateId matches', () {
      expect(const TemplateColumn('t1'), const TemplateColumn('t1'));
    });

    test('not equal for a different templateId', () {
      expect(const TemplateColumn('t1') == const TemplateColumn('t2'), isFalse);
    });
  });

  test('a DayColumn is never equal to a TemplateColumn', () {
    expect(
      const DayColumn.internal(DateTime(2026, 9, 9)) ==
          const TemplateColumn('2026-09-09'),
      isFalse,
    );
  });

  group('anchorDateFor', () {
    test('returns the DayColumn\'s own date', () {
      final date = DateTime(2026, 9, 9);
      expect(anchorDateFor(DayColumn(date)), date);
    });

    test('returns templateAnchorDate for a TemplateColumn', () {
      expect(anchorDateFor(const TemplateColumn('t1')), templateAnchorDate);
    });
  });
}
```

(`DayColumn.internal` is a throwaway name only until Step 3 defines the real constructor as plain `DayColumn(...)` — skip that and write the tests directly against `DayColumn(...)`/`TemplateColumn(...)` as shown in Step 3's implementation; there is no separate `.internal` constructor. Use `DayColumn(...)` in the test file, not `DayColumn.internal(...)`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/schedule_column_test.dart`
Expected: FAIL — `schedule_column.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/day/models/schedule_column.dart

/// Identifies which column of a schedule grid a block belongs to — a
/// calendar day, or a template — independent of the `DateTime` a
/// [TimeObject] uses for its time-of-day, which for a template block
/// always carries [templateAnchorDate] and means nothing on its own: the
/// column identity is this type, never a block's own date.
sealed class ScheduleColumn {
  const ScheduleColumn();
}

/// A real calendar day. Equality and hashing are by calendar day
/// (year/month/day), ignoring time of day, so callers may pass a freshly
/// constructed but same-day [DateTime] without changing identity — the
/// same guarantee `dayGridKeyFor`'s docs used to describe directly.
class DayColumn extends ScheduleColumn {
  const DayColumn(this.date);

  final DateTime date;

  @override
  bool operator ==(Object other) =>
      other is DayColumn &&
      other.date.year == date.year &&
      other.date.month == date.month &&
      other.date.day == date.day;

  @override
  int get hashCode => Object.hash(date.year, date.month, date.day);

  @override
  String toString() => 'DayColumn($date)';
}

/// One template, identified by [templateId].
class TemplateColumn extends ScheduleColumn {
  const TemplateColumn(this.templateId);

  final String templateId;

  @override
  bool operator ==(Object other) =>
      other is TemplateColumn && other.templateId == templateId;

  @override
  int get hashCode => templateId.hashCode;

  @override
  String toString() => 'TemplateColumn($templateId)';
}

/// The fixed date every template block's `start`/`end` carries as their
/// date component. Never read as meaning anything — a template block's
/// column identity is its [TemplateColumn], not this date. Exists purely
/// so [TimeObject] can keep using `DateTime` for time-of-day arithmetic
/// without a template needing a real calendar date.
final DateTime templateAnchorDate = DateTime(2000, 1, 1);

/// The `DateTime` the grid-math helpers in `day_new_block.dart` should
/// anchor to for [column]: the real date for a [DayColumn], or
/// [templateAnchorDate] for a [TemplateColumn].
DateTime anchorDateFor(ScheduleColumn column) => switch (column) {
  DayColumn(:final date) => date,
  TemplateColumn() => templateAnchorDate,
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/schedule_column_test.dart`
Expected: PASS (after fixing the test file to call `DayColumn(...)` directly, not `DayColumn.internal(...)` — there is only one constructor).

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/models/schedule_column.dart test/unit/schedule_column_test.dart
git commit -m "feat: add ScheduleColumn to split block identity from time-of-day"
```

---

### Task 2: `ScheduleController` + `DayScheduleController`

**Files:**
- Create: `lib/features/day/schedule_controller.dart`
- Create: `lib/features/day/day_schedule_controller.dart`
- Test: `test/unit/day_schedule_controller_test.dart`

**Interfaces:**
- Consumes: `ScheduleColumn`/`DayColumn` (Task 1); `dayBlocksProvider`, `dayBlocksRepositoryProvider` (`lib/features/day/providers.dart`, unchanged in this task).
- Produces: `abstract class ScheduleController { List<TimeObject>? blocksOf(Ref ref, ScheduleColumn column); Future<void> moveBlock(Ref ref, {required TimeObject block, required ScheduleColumn fromColumn, required ScheduleColumn toColumn, required DateTime newStart, required DateTime newEnd}); }`, `class DayScheduleController extends ScheduleController`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/day_schedule_controller_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_schedule_controller.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';

/// Riverpod's `Ref` has no public constructor; reading this trivial
/// provider is the standard way to obtain one from a `ProviderContainer`
/// in a plain (non-widget) test.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  group('DayScheduleController', () {
    test('blocksOf reads the day blocks provider for the column\'s date', () async {
      final container = ProviderContainer();
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/day_schedule_controller_test.dart`
Expected: FAIL — `day_schedule_controller.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/day/schedule_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// Reads and moves the blocks belonging to a [ScheduleColumn], hiding
/// whether they're backed by the day feature's providers (a [DayColumn])
/// or a template's own providers (a [TemplateColumn]) from the shared
/// drag/resize code in `providers.dart` — `DragNotifier`/`ResizeNotifier`
/// never need to know which.
abstract class ScheduleController {
  const ScheduleController();

  /// The currently loaded blocks for [column], or `null` while still
  /// loading.
  List<TimeObject>? blocksOf(Ref ref, ScheduleColumn column);

  /// Moves [block] from [fromColumn] to [toColumn] (the same column for a
  /// resize, which never changes column), updating its start/end to
  /// [newStart]/[newEnd], then refreshes both columns' providers.
  Future<void> moveBlock(
    Ref ref, {
    required TimeObject block,
    required ScheduleColumn fromColumn,
    required ScheduleColumn toColumn,
    required DateTime newStart,
    required DateTime newEnd,
  });
}
```

```dart
// lib/features/day/day_schedule_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/schedule_controller.dart';

/// A [ScheduleController] backed by [dayBlocksProvider]/
/// [dayBlocksRepositoryProvider]. Every [ScheduleColumn] it's given must
/// be a [DayColumn].
class DayScheduleController extends ScheduleController {
  const DayScheduleController();

  DateTime _dateOf(ScheduleColumn column) => (column as DayColumn).date;

  @override
  List<TimeObject>? blocksOf(Ref ref, ScheduleColumn column) =>
      ref.read(dayBlocksProvider(_dateOf(column))).value;

  @override
  Future<void> moveBlock(
    Ref ref, {
    required TimeObject block,
    required ScheduleColumn fromColumn,
    required ScheduleColumn toColumn,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final fromDate = _dateOf(fromColumn);
    final toDate = _dateOf(toColumn);
    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.move(
      block,
      fromDate: fromDate,
      toDate: toDate,
      newStart: newStart,
      newEnd: newEnd,
    );
    ref.invalidate(dayBlocksProvider(fromDate));
    ref.invalidate(dayBlocksProvider(toDate));
    await ref.read(dayBlocksProvider(fromDate).future);
    await ref.read(dayBlocksProvider(toDate).future);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/day_schedule_controller_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/schedule_controller.dart lib/features/day/day_schedule_controller.dart test/unit/day_schedule_controller_test.dart
git commit -m "feat: add ScheduleController and DayScheduleController"
```

---

### Task 3: Generalize `DragState`/`ResizeState` to `ScheduleColumn`

**Files:**
- Modify: `lib/features/day/models/drag_state.dart`
- Modify: `lib/features/day/models/resize_state.dart`
- Modify: `test/unit/drag_state_test.dart`
- Modify: `test/unit/resize_state_test.dart`

**Interfaces:**
- Consumes: `ScheduleColumn`, `DayColumn` (Task 1).
- Produces: `DragState.originalColumn`/`targetColumn` (`ScheduleColumn`/`ScheduleColumn?`, was `originalDate`/`targetDate`); `ResizeState.column` (`ScheduleColumn`, was `date`). `TimeObject block`, `pointerGlobalPosition`, `targetStart`/`draftStart`/`draftEnd`, `edge` are unchanged.

- [ ] **Step 1: Update `drag_state.dart`**

```dart
// lib/features/day/models/drag_state.dart
import 'package:flutter/material.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// The in-flight state of a block being dragged to a new time/column.
///
/// `null` (held by `dragStateProvider`, not this class) means no drag is
/// in progress.
class DragState {
  /// Creates a [DragState].
  const DragState({
    required this.block,
    required this.originalColumn,
    required this.targetColumn,
    required this.targetStart,
    required this.pointerGlobalPosition,
  });

  /// The block being dragged, as it was before the drag started.
  final TimeObject block;

  /// The column [block] belonged to when the drag started.
  final ScheduleColumn originalColumn;

  /// The column the landzone shadow is currently shown on, or `null` when
  /// the pointer is over no column at all — in which case releasing here
  /// would cancel the move, and no landzone is drawn anywhere.
  final ScheduleColumn? targetColumn;

  /// The 15-minute-grid-aligned time the landzone shadow currently starts
  /// at, or `null` alongside a `null` [targetColumn].
  final DateTime? targetStart;

  /// The dragging pointer's last known position in global (screen)
  /// coordinates, used for edge-triggered day/week paging.
  final Offset pointerGlobalPosition;

  /// Whether the drag currently has a valid landzone to drop onto.
  bool get hasTarget => targetColumn != null && targetStart != null;

  /// Returns a copy of this state with the given fields replaced.
  ///
  /// Pass [clearTarget] to drop the landzone entirely (the pointer is over
  /// no column); it wins over [targetColumn]/[targetStart], which
  /// otherwise keep their current values when omitted.
  DragState copyWith({
    ScheduleColumn? targetColumn,
    DateTime? targetStart,
    Offset? pointerGlobalPosition,
    bool clearTarget = false,
  }) {
    return DragState(
      block: block,
      originalColumn: originalColumn,
      targetColumn: clearTarget ? null : (targetColumn ?? this.targetColumn),
      targetStart: clearTarget ? null : (targetStart ?? this.targetStart),
      pointerGlobalPosition:
          pointerGlobalPosition ?? this.pointerGlobalPosition,
    );
  }
}
```

- [ ] **Step 2: Update `resize_state.dart`**

```dart
// lib/features/day/models/resize_state.dart
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// Which edge of a block a resize drag is moving.
enum ResizeEdge {
  /// The drag is moving the block's start time.
  start,

  /// The drag is moving the block's end time.
  end,
}

/// The in-flight state of a block being resized by dragging one of its
/// edges.
///
/// `null` (held by `resizeStateProvider`, not this class) means no resize
/// is in progress.
class ResizeState {
  /// Creates a [ResizeState].
  const ResizeState({
    required this.block,
    required this.column,
    required this.edge,
    required this.draftStart,
    required this.draftEnd,
  });

  /// The block being resized, as it was before the resize started.
  final TimeObject block;

  /// The column [block] belongs to. Resizing never changes it.
  final ScheduleColumn column;

  /// Which edge of the block is being dragged.
  final ResizeEdge edge;

  /// The 15-minute-grid-aligned, clamped start time the draft shadow
  /// currently shows.
  final DateTime draftStart;

  /// The 15-minute-grid-aligned, clamped end time the draft shadow
  /// currently shows.
  final DateTime draftEnd;

  /// Returns a copy of this state with the given fields replaced.
  ResizeState copyWith({DateTime? draftStart, DateTime? draftEnd}) {
    return ResizeState(
      block: block,
      column: column,
      edge: edge,
      draftStart: draftStart ?? this.draftStart,
      draftEnd: draftEnd ?? this.draftEnd,
    );
  }
}
```

- [ ] **Step 3: Update the two test files**

In `test/unit/drag_state_test.dart`: replace every `originalDate: DateTime(2026, 9, 9)` with `originalColumn: const DayColumn(DateTime(2026, 9, 9))` (const-ness of the DateTime literal is unaffected — keep `DateTime(...)` non-const inside if the surrounding context isn't const, matching existing style), every `targetDate: DateTime(...)` with `targetColumn: DayColumn(DateTime(...))`, and every assertion `state.originalDate`/`state.targetDate` with `state.originalColumn`/`state.targetColumn` compared against the matching `DayColumn(...)`. Add `import 'package:taskframe/features/day/models/schedule_column.dart';`.

In `test/unit/resize_state_test.dart`: replace every `date: DateTime(2026, 9, 9)` with `column: DayColumn(DateTime(2026, 9, 9))`, and `state.date` assertions with `state.column` compared against `DayColumn(DateTime(2026, 9, 9))`. Add the same import.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/drag_state_test.dart test/unit/resize_state_test.dart`
Expected: PASS. (`flutter test` as a whole will still fail here — `providers.dart`, `drag_target_resolver.dart`, and `day_grid.dart` still reference the old field names; that's fixed in Tasks 4–6. Confirm with `flutter analyze` that the *only* new errors are in those not-yet-updated files.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/models/drag_state.dart lib/features/day/models/resize_state.dart test/unit/drag_state_test.dart test/unit/resize_state_test.dart
git commit -m "refactor: generalize DragState/ResizeState to ScheduleColumn"
```

---

### Task 4: Generalize `drag_target_resolver.dart`

**Files:**
- Modify: `lib/features/day/widgets/drag_target_resolver.dart`
- Modify: `test/widget/drag_target_resolver_test.dart`

**Interfaces:**
- Consumes: `ScheduleColumn`, `DayColumn`, `anchorDateFor` (Task 1).
- Produces: `GlobalKey scheduleGridKeyFor(ScheduleColumn column)` (was `dayGridKeyFor(DateTime date)`), `int scheduleGridKeyCacheSizeForTest()` (was `dayGridKeyCacheSizeForTest()`), `({ScheduleColumn column, DateTime start})? resolveDragTarget({required Offset globalPosition, required DaySettings settings, required double slotHeight, required Duration blockDuration, List<ScheduleColumn>? candidateColumns})` (was keyed by `DateTime`/`candidateDates`, returned `({DateTime date, DateTime start})?`).

- [ ] **Step 1: Rewrite the implementation**

```dart
// lib/features/day/widgets/drag_target_resolver.dart
import 'package:flutter/widgets.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';

/// One [GlobalKey] per [ScheduleColumn], handed out by [scheduleGridKeyFor].
final Map<ScheduleColumn, GlobalKey> _scheduleGridKeys =
    <ScheduleColumn, GlobalKey>{};

/// The [GlobalKey] a `DayGrid` for [column] is built with, so
/// [resolveDragTarget] can find its render box regardless of which page or
/// screen a drag started in.
///
/// Memoized per [column] — [DayColumn]'s own equality already normalizes
/// to calendar day, so callers may rebuild their column lists with fresh
/// (but `==`-equal) values on every build without changing the key.
///
/// Do not "simplify" this back to `GlobalObjectKey(column)`: that key
/// type's equality is `identical(other.value, value)`, so a freshly
/// constructed (but `==`-equal) [ScheduleColumn] yields a key that
/// compares *unequal* to the previous build's, making `Widget.canUpdate`
/// return false and forcing Flutter to destroy and reinflate the whole
/// `DayGrid` element — losing its open draft and now-timer — on every
/// rebuild.
GlobalKey scheduleGridKeyFor(ScheduleColumn column) {
  _schedulePrune();
  return _scheduleGridKeys.putIfAbsent(column, GlobalKey.new);
}

/// Whether a prune sweep has already been scheduled for the current
/// frame, so a page with many columns doesn't queue one callback per
/// [scheduleGridKeyFor] call.
bool _pruneScheduled = false;

/// Queues [_pruneUnmountedKeys] to run once, after the current frame
/// finishes.
///
/// Deferred to a post-frame callback rather than run inline: a page
/// building several columns (e.g. a week view's 7 dates) calls
/// [scheduleGridKeyFor] once per column in the same synchronous build,
/// before any of that frame's widgets have mounted — pruning inline right
/// then would see every one of those brand-new keys as still
/// `currentContext == null` and wrongly discard them before they ever get
/// the chance to attach. By the end of the frame, every key requested
/// during it is either mounted (kept) or was never actually built (safe
/// to drop).
void _schedulePrune() {
  if (_pruneScheduled) return;
  _pruneScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _pruneScheduled = false;
    _pruneUnmountedKeys();
  });
}

/// Drops every memoized key whose `DayGrid` has since unmounted, so a long
/// session paging through many columns doesn't grow [_scheduleGridKeys]
/// forever.
void _pruneUnmountedKeys() {
  _scheduleGridKeys.removeWhere((_, key) => key.currentContext == null);
}

/// The number of columns currently memoized in [_scheduleGridKeys].
@visibleForTesting
int scheduleGridKeyCacheSizeForTest() => _scheduleGridKeys.length;

/// Finds which column [globalPosition] currently falls over, and the
/// 15-minute slot within it, by looking up each candidate column's
/// mounted widget via [scheduleGridKeyFor].
///
/// [candidateColumns] defaults to *every* column [scheduleGridKeyFor] has
/// ever been asked for; only the handful whose `DayGrid` is mounted and
/// attached right now can match, so the result always reflects whatever
/// page is visible at the moment of the call rather than whatever was
/// visible when a drag started. Pass [candidateColumns] explicitly only to
/// restrict the search (tests do).
///
/// Returns `null` if [globalPosition] isn't over any mounted column, or if
/// it's over a column but a block of [blockDuration] dropped at the
/// snapped slot there would end after that column's boundary — see
/// [dayEndFor]. Either way, the caller's existing "no valid column"
/// fallback (previewing the snap-back at the block's own original
/// position) applies.
({ScheduleColumn column, DateTime start})? resolveDragTarget({
  required Offset globalPosition,
  required DaySettings settings,
  required double slotHeight,
  required Duration blockDuration,
  List<ScheduleColumn>? candidateColumns,
}) {
  final columns = candidateColumns ?? _scheduleGridKeys.keys.toList(growable: false);
  for (final column in columns) {
    final renderObject =
        scheduleGridKeyFor(column).currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) continue;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    if (!rect.contains(globalPosition)) continue;

    final anchor = anchorDateFor(column);
    final start = slotStartForOffset(
      day: anchor,
      dy: globalPosition.dy - topLeft.dy,
      settings: settings,
      slotHeight: slotHeight,
    );
    if (start == null) continue;
    if (start.add(blockDuration).isAfter(dayEndFor(anchor, settings))) continue;

    return (column: column, start: start);
  }
  return null;
}
```

- [ ] **Step 2: Update the test file**

In `test/widget/drag_target_resolver_test.dart`:
- Add `import 'package:taskframe/features/day/models/schedule_column.dart';`.
- Replace `final _dates = [DateTime(2026, 9, 9), DateTime(2026, 9, 10)];` with `final _columns = [DayColumn(DateTime(2026, 9, 9)), DayColumn(DateTime(2026, 9, 10))];`.
- In `_pumpTwoColumns`, replace `for (final date in _dates) SizedBox(key: dayGridKeyFor(date), ...)` with `for (final column in _columns) SizedBox(key: scheduleGridKeyFor(column), ...)`.
- Replace every `candidateDates: _dates` with `candidateColumns: _columns`.
- Replace every `target?.date` assertion with `target?.column`, comparing against the matching `_columns[i]` (a `DayColumn`) instead of a bare `DateTime`.
- In the `dayGridKeyFor cache growth` group: rename to `scheduleGridKeyFor cache growth`; replace `manyDates`/`dayGridKeyFor(date)` with a list of `DayColumn`s and `scheduleGridKeyFor(column)`; replace `dayGridKeyCacheSizeForTest()` with `scheduleGridKeyCacheSizeForTest()`.

- [ ] **Step 3: Run test to verify it passes**

Run: `flutter test test/widget/drag_target_resolver_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/features/day/widgets/drag_target_resolver.dart test/widget/drag_target_resolver_test.dart
git commit -m "refactor: generalize drag_target_resolver to ScheduleColumn"
```

---

### Task 5: Generalize `DragNotifier`/`ResizeNotifier`

**Files:**
- Modify: `lib/features/day/providers.dart`
- Modify: `test/unit/drag_state_provider_test.dart`
- Modify: `test/unit/resize_state_provider_test.dart`

**Interfaces:**
- Consumes: `ScheduleColumn`, `DayColumn` (Task 1); `ScheduleController`, `DayScheduleController` (Task 2); `DragState.originalColumn`/`targetColumn`, `ResizeState.column` (Task 3).
- Produces: `DragNotifier.start({required TimeObject block, required ScheduleColumn originalColumn, required ScheduleController controller, required Offset pointerGlobalPosition, int? pointer, DragTargetResolver? resolveTarget})`; `DragNotifier.updatePointer(Offset globalPosition, {ScheduleColumn? targetColumn, DateTime? targetStart})`; `typedef DragTargetResolver = ({ScheduleColumn column, DateTime start})? Function(Offset globalPosition)`; `ResizeNotifier.start({required TimeObject block, required ScheduleColumn column, required ScheduleController controller, required ResizeEdge edge})`.

- [ ] **Step 1: Edit `providers.dart`'s imports and `DragTargetResolver`**

Add imports:
```dart
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
```

Replace the `DragTargetResolver` typedef:
```dart
/// Resolves a global pointer position into the column and 15-minute slot
/// under it, or `null` when the pointer is over no column.
///
/// Supplied by the widget that starts a drag (it knows the grid's
/// settings and slot height) and then called by [DragNotifier] for the
/// rest of the drag's life, so target resolution keeps working after that
/// widget is gone.
typedef DragTargetResolver = ({ScheduleColumn column, DateTime start})?
    Function(Offset globalPosition);
```

- [ ] **Step 2: Edit `DragNotifier`**

Replace its body (the `_pointer`/`_globalRoute` fields are unchanged) with:

```dart
class DragNotifier extends Notifier<DragState?> {
  int? _pointer;
  PointerRoute? _globalRoute;
  DragTargetResolver? _resolveTarget;
  ScheduleController? _controller;

  @override
  DragState? build() {
    ref.onDispose(_releasePointer);
    return null;
  }

  /// Begins dragging [block], which belonged to [originalColumn]. The
  /// landzone starts at the block's own current column/time. [controller]
  /// is used for every subsequent read/move this drag makes, so it must
  /// match [originalColumn]'s kind (a [DayScheduleController] for a
  /// [DayColumn], and so on).
  void start({
    required TimeObject block,
    required ScheduleColumn originalColumn,
    required ScheduleController controller,
    required Offset pointerGlobalPosition,
    int? pointer,
    DragTargetResolver? resolveTarget,
  }) {
    _controller = controller;
    state = DragState(
      block: block,
      originalColumn: originalColumn,
      targetColumn: originalColumn,
      targetStart: block.start,
      pointerGlobalPosition: pointerGlobalPosition,
    );
    _takePointer(pointer, resolveTarget);
  }

  /// Updates the dragging pointer's position and its landzone.
  ///
  /// [targetColumn]/[targetStart] are the freshly resolved target under
  /// the pointer; passing `null` for them means the pointer is over no
  /// column right now, which *clears* the landzone rather than leaving a
  /// stale one showing. That keeps what the user sees honest: releasing
  /// where no landzone is drawn cancels the move. Does nothing if no drag
  /// is in progress.
  void updatePointer(
    Offset globalPosition, {
    ScheduleColumn? targetColumn,
    DateTime? targetStart,
  }) {
    final current = state;
    if (current == null) return;
    var resolvedColumn = targetColumn;
    var resolvedStart = targetStart;
    if (resolvedColumn != null &&
        resolvedStart != null &&
        _overlapsExisting(current.block, resolvedColumn, resolvedStart)) {
      resolvedColumn = current.originalColumn;
      resolvedStart = current.block.start;
    }
    state = current.copyWith(
      targetColumn: resolvedColumn,
      targetStart: resolvedStart,
      pointerGlobalPosition: globalPosition,
      clearTarget: resolvedColumn == null || resolvedStart == null,
    );
  }

  /// Whether placing [dragged] at [column]/[start] would overlap another
  /// block already on [column].
  bool _overlapsExisting(TimeObject dragged, ScheduleColumn column, DateTime start) {
    final blocks = _controller?.blocksOf(ref, column);
    if (blocks == null) return false;
    final end = start.add(dragged.end.difference(dragged.start));
    return blocks.any(
      (block) => block.id != dragged.id && block.overlaps(start, end),
    );
  }

  /// Commits the current drag: moves the block to its current landzone
  /// column/time via [_controller], then clears the drag. Does nothing if
  /// no drag is in progress; cancels instead if there is no valid
  /// landzone.
  Future<void> drop() async {
    final current = state;
    if (current == null) return;
    final toColumn = current.targetColumn;
    final newStart = current.targetStart;
    if (toColumn == null || newStart == null) {
      cancel();
      return;
    }
    final controller = _controller!;
    // TODO(alex): clearing the drag state before awaiting `moveBlock` means
    // a failing move would surface as an unhandled async error and a
    // silent UI no-op (the block snaps back with no explanation). Fine for
    // today's in-memory stubs, which cannot fail; must be revisited before
    // any real or networked repository backs this.
    state = null;
    _releasePointer();

    final duration = current.block.end.difference(current.block.start);
    await controller.moveBlock(
      ref,
      block: current.block,
      fromColumn: current.originalColumn,
      toColumn: toColumn,
      newStart: newStart,
      newEnd: newStart.add(duration),
    );
  }

  /// Abandons the current drag without moving the block.
  void cancel() {
    state = null;
    _releasePointer();
  }

  void _takePointer(int? pointer, DragTargetResolver? resolveTarget) {
    _releasePointer();
    if (pointer == null) return;
    _pointer = pointer;
    _resolveTarget = resolveTarget;
    final route = _handlePointerEvent;
    _globalRoute = route;
    GestureBinding.instance.pointerRouter.addGlobalRoute(route);
  }

  void _releasePointer() {
    final route = _globalRoute;
    if (route != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(route);
    }
    _globalRoute = null;
    _pointer = null;
    _resolveTarget = null;
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    final current = state;
    if (current == null) {
      _releasePointer();
      return;
    }

    if (event is PointerMoveEvent) {
      final target = _resolveTarget?.call(event.position);
      updatePointer(
        event.position,
        targetColumn: target?.column ?? current.originalColumn,
        targetStart: target?.start ?? current.block.start,
      );
    } else if (event is PointerUpEvent) {
      final target = _resolveTarget?.call(event.position);
      if (target == null) {
        cancel();
      } else {
        updatePointer(
          event.position,
          targetColumn: target.column,
          targetStart: target.start,
        );
        unawaited(drop());
      }
    } else if (event is PointerCancelEvent) {
      cancel();
    }
  }
}
```

(Class-level doc comment carries over unchanged from the original — keep it.)

- [ ] **Step 3: Edit `ResizeNotifier`**

```dart
class ResizeNotifier extends Notifier<ResizeState?> {
  ScheduleController? _controller;

  @override
  ResizeState? build() => null;

  /// Begins resizing [block] on [column] from [edge]. The draft starts out
  /// equal to the block's own current start/end. [controller] is used for
  /// every subsequent read/commit this resize makes.
  void start({
    required TimeObject block,
    required ScheduleColumn column,
    required ScheduleController controller,
    required ResizeEdge edge,
  }) {
    _controller = controller;
    state = ResizeState(
      block: block,
      column: column,
      edge: edge,
      draftStart: block.start,
      draftEnd: block.end,
    );
  }

  /// Updates the dragged edge's draft time to [candidate] (already
  /// snapped to the 15-minute grid), clamped so the block never shrinks
  /// below [_minBlockDuration] and never overlaps another block on
  /// [ResizeState.column].
  void update(DateTime candidate) {
    final current = state;
    if (current == null) return;
    final others = (_controller?.blocksOf(ref, current.column) ?? [])
        .where((block) => block.id != current.block.id);

    if (current.edge == ResizeEdge.end) {
      var newEnd = candidate;
      final minEnd = current.draftStart.add(_minBlockDuration);
      if (newEnd.isBefore(minEnd)) newEnd = minEnd;
      for (final block in others) {
        if (block.start.isAfter(current.draftStart) &&
            block.start.isBefore(newEnd)) {
          newEnd = block.start;
        }
      }
      state = current.copyWith(draftEnd: newEnd);
    } else {
      var newStart = candidate;
      final maxStart = current.draftEnd.subtract(_minBlockDuration);
      if (newStart.isAfter(maxStart)) newStart = maxStart;
      for (final block in others) {
        if (block.end.isBefore(current.draftEnd) &&
            block.end.isAfter(newStart)) {
          newStart = block.end;
        }
      }
      state = current.copyWith(draftStart: newStart);
    }
  }

  /// Commits the current resize: persists the draft start/end via
  /// [_controller], then clears the resize. Does nothing if no resize is
  /// in progress.
  Future<void> commit() async {
    final current = state;
    if (current == null) return;
    final controller = _controller!;
    state = null;

    await controller.moveBlock(
      ref,
      block: current.block,
      fromColumn: current.column,
      toColumn: current.column,
      newStart: current.draftStart,
      newEnd: current.draftEnd,
    );
  }

  /// Abandons the current resize without changing the block.
  void cancel() {
    state = null;
  }
}
```

`dragStateForDate`/`resizeStateForDate` (the `.select` projection helpers) become:

```dart
/// Projects [dragState] to the value a `DayGrid` for [column] actually
/// cares about, collapsing to `null` whenever [column] is neither the
/// drag's origin nor its current landzone target.
DragState? dragStateForColumn(DragState? dragState, ScheduleColumn column) {
  if (dragState == null) return null;
  final relevant =
      dragState.originalColumn == column || dragState.targetColumn == column;
  return relevant ? dragState : null;
}

/// Projects [resizeState] to the value a `DayGrid` for [column] actually
/// cares about, collapsing to `null` whenever the resize belongs to some
/// other column. See [dragStateForColumn], its drag equivalent.
ResizeState? resizeStateForColumn(ResizeState? resizeState, ScheduleColumn column) {
  if (resizeState == null) return null;
  return resizeState.column == column ? resizeState : null;
}
```

(rename from `dragStateForDate`/`resizeStateForDate` — Task 6 updates `day_grid.dart`'s two call sites.)

- [ ] **Step 4: Update `test/unit/drag_state_provider_test.dart`**

Add `import 'package:taskframe/features/day/day_schedule_controller.dart';` and `import 'package:taskframe/features/day/models/schedule_column.dart';`. In every `.start(...)` call, replace `originalDate: DateTime(...)` with `originalColumn: DayColumn(DateTime(...))` and add `controller: const DayScheduleController(),`. In every `.updatePointer(..., targetDate: ..., targetStart: ...)` call, replace `targetDate:` with `targetColumn: DayColumn(...)`. Replace every `state.originalDate`/`state.targetDate` assertion with `state.originalColumn`/`state.targetColumn` compared against the matching `DayColumn(...)`. `dayBlocksProvider(...)` calls are otherwise unchanged (still `DateTime`-keyed).

- [ ] **Step 5: Update `test/unit/resize_state_provider_test.dart`**

Add the same two imports. In every `.start(...)` call, replace `date: _date` with `column: DayColumn(_date)` and add `controller: const DayScheduleController(),`. Replace every `state.date` assertion with `state.column` compared against `DayColumn(_date)`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/unit/drag_state_provider_test.dart test/unit/resize_state_provider_test.dart`
Expected: PASS. `flutter analyze` should now show remaining errors only in `day_grid.dart` (Task 6) and `block_edit_modal.dart`/`day_screen.dart` (Tasks 7–8).

- [ ] **Step 7: Commit**

```bash
git add lib/features/day/providers.dart test/unit/drag_state_provider_test.dart test/unit/resize_state_provider_test.dart
git commit -m "refactor: generalize DragNotifier/ResizeNotifier to ScheduleColumn/ScheduleController"
```

---

### Task 6: Generalize `DayGrid`/`_DraggableBlock`

**Files:**
- Modify: `lib/features/day/widgets/day_grid.dart`
- Modify: `test/widget/day_grid_test.dart`

**Interfaces:**
- Consumes: `ScheduleColumn`, `DayColumn` (Task 1); `ScheduleController`, `DayScheduleController` (Task 2); `scheduleGridKeyFor`, `resolveDragTarget` (Task 4); `dragStateForColumn`, `resizeStateForColumn` (Task 5); `showBlockEditModal` (Task 7, forward reference — see note below).
- Produces: `DayGrid` gains two new required constructor params, `column: ScheduleColumn` and `controller: ScheduleController`, alongside its existing `date: DateTime` (unchanged — still drives grid math/"now" line).

Note: `_openEditModal` calls `showBlockEditModal`, whose signature Task 7 also changes (`date:` → `column:`, plus a new `actions:` param). Do this task's `_openEditModal` edit using the **post-Task-7** signature directly (`showBlockEditModal(context: context, column: widget.column, actions: widget.actions, block: block)`), and add a matching new `actions: ScheduleBlockActions` field to `DayGrid` now, in this task — it's simplest to thread both new dependencies (`controller` for drag/resize, `actions` for the edit modal) through `DayGrid` together. `flutter analyze` will still show an error on this one line until Task 7 actually changes `showBlockEditModal`'s signature; that's expected and resolves in Task 7's Step 1.

- [ ] **Step 1: Add imports and the two new fields to `DayGrid`**

Add imports:
```dart
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
import 'package:taskframe/features/day/widgets/schedule_block_actions.dart';
```

In `DayGrid`'s constructor and field list, add:
```dart
  const new({
    required this.date,
    required this.column,
    required this.controller,
    required this.actions,
    required this.blocks,
    required this.settings,
    required this.slotHeight,
    required this.onCreateBlock,
    this.showHourLabels = true,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
    this.onSwipeCancel,
    super.key,
  });

  /// The date this grid shows, used to resolve tap positions into times
  /// and to drive the "now" line — for a template column this is always
  /// [templateAnchorDate], so the "now" line never applies.
  final DateTime date;

  /// This grid's column identity — used for provider/key lookups and as
  /// the drag/resize origin, independent of [date].
  final ScheduleColumn column;

  /// Reads/moves this column's blocks during a drag or resize, supplied
  /// by the caller (`DayScreen` or `TemplatesScreen`) so this widget never
  /// needs to know which feature it's showing.
  final ScheduleController controller;

  /// Supplies the block-edit modal's read/write access to this column's
  /// blocks, supplied by the same caller as [controller].
  final ScheduleBlockActions actions;
```

(keep every other existing field as-is.)

- [ ] **Step 2: Update `_DayGridState` to use `column`/`controller`/`actions`**

Replace the `dragState`/`resizeState`/`hiddenBlockId`/`landzoneStart` block in `build()`:
```dart
    final dragState = ref.watch(
      dragStateProvider.select((state) => dragStateForColumn(state, widget.column)),
    );
    final resizeState = ref.watch(
      resizeStateProvider.select(
        (state) => resizeStateForColumn(state, widget.column),
      ),
    );
    final hiddenBlockId =
        dragState != null && dragState.originalColumn == widget.column
        ? dragState.block.id
        : resizeState != null && resizeState.column == widget.column
        ? resizeState.block.id
        : null;
    final landzoneStart =
        dragState != null && dragState.targetColumn == widget.column
        ? dragState.targetStart
        : null;
```

Replace `resizeState != null && resizeState.date == widget.date` (guarding the resize-draft overlay near the bottom of `build()`) with `resizeState != null && resizeState.column == widget.column`.

Replace `_openEditModal`:
```dart
  void _openEditModal(TimeObject block) {
    unawaited(
      showBlockEditModal(
        context: context,
        column: widget.column,
        actions: widget.actions,
        block: block,
      ),
    );
  }
```

- [ ] **Step 3: Update `_DraggableBlock` and `_DraggableBlockState`**

In `DayGrid.build()`'s per-block loop, the `_DraggableBlock(...)` construction gains two new args:
```dart
              child: _DraggableBlock(
                block: block,
                column: widget.column,
                controller: widget.controller,
                date: widget.date,
                settings: widget.settings,
                slotHeight: widget.slotHeight,
                ...
```

In `_DraggableBlock`'s own constructor/fields, add `column`/`controller` alongside the existing `date`:
```dart
class _DraggableBlock extends ConsumerStatefulWidget {
  const _DraggableBlock({
    required this.block,
    required this.column,
    required this.controller,
    required this.date,
    required this.settings,
    ...
  });

  final TimeObject block;
  final ScheduleColumn column;
  final ScheduleController controller;
  final DateTime date;
  ...
```

In `_DraggableBlockState._start`:
```dart
  void _start(Offset globalPosition) {
    final settings = widget.settings;
    final slotHeight = widget.slotHeight;
    final controller = widget.controller;
    final blockDuration = widget.block.end.difference(widget.block.start);

    ref
        .read(dragStateProvider.notifier)
        .start(
          block: widget.block,
          originalColumn: widget.column,
          controller: controller,
          pointerGlobalPosition: globalPosition,
          pointer: _pointer,
          resolveTarget: (position) => resolveDragTarget(
            globalPosition: position,
            settings: settings,
            slotHeight: slotHeight,
            blockDuration: blockDuration,
          ),
        );
  }
```

In `_startResize`:
```dart
  void _startResize(ResizeEdge edge) {
    ref
        .read(resizeStateProvider.notifier)
        .start(
          block: widget.block,
          column: widget.column,
          controller: widget.controller,
          edge: edge,
        );
  }
```

In `_updateResize`, the render-object lookup switches keys:
```dart
    final renderObject = scheduleGridKeyFor(widget.column).currentContext?.findRenderObject();
```
(the rest of `_updateResize` is unchanged — it still resolves the candidate time via `widget.date`/`widget.settings`/`widget.slotHeight`.)

- [ ] **Step 4: Update `test/widget/day_grid_test.dart`**

At the top, add:
```dart
import 'package:taskframe/features/day/day_schedule_block_actions.dart';
import 'package:taskframe/features/day/day_schedule_controller.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
```

For every one of the 7 `DayGrid(...)` constructions found via `grep -n "DayGrid(" test/widget/day_grid_test.dart`, add three lines right after `date: _date,` (or, for the two that also pass an explicit `key:`, replace `key: dayGridKeyFor(_date)` with `key: scheduleGridKeyFor(const DayColumn(_date))`):
```dart
                  column: const DayColumn(_date),
                  controller: const DayScheduleController(),
                  actions: dayScheduleBlockActions,
```
(match the surrounding indentation at each call site.)

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/widget/day_grid_test.dart`
Expected: Still FAILS at this point — `schedule_block_actions.dart`/`day_schedule_block_actions.dart` don't exist until Task 7. That's expected; proceed directly to Task 7 before attempting a green run of this file. (If executing tasks with review checkpoints between each, note this explicitly rather than reporting false failure.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/day/widgets/day_grid.dart test/widget/day_grid_test.dart
git commit -m "refactor: generalize DayGrid/_DraggableBlock to ScheduleColumn/ScheduleController"
```

---

### Task 7: `ScheduleBlockActions` + generalize `BlockEditModal`

**Files:**
- Create: `lib/features/day/widgets/schedule_block_actions.dart`
- Create: `lib/features/day/day_schedule_block_actions.dart`
- Modify: `lib/features/day/widgets/block_edit_modal.dart`
- Modify: `test/widget/block_edit_modal_test.dart`
- Modify: `test/widget/day_grid_test.dart` (only to confirm it now passes — no further edits expected)

**Interfaces:**
- Consumes: `ScheduleColumn`, `DayColumn`, `anchorDateFor` (Task 1); `dayBlocksProvider` (`providers.dart`, unchanged).
- Produces: `class ScheduleBlockActions { final List<TimeObject>? Function(WidgetRef ref, ScheduleColumn column) watchBlocks; final Future<void> Function(WidgetRef ref, ScheduleColumn column, TimeObject block, {String? title, DateTime? start, DateTime? end, BlockKind? kind, String? categoryId}) updateBlock; final Future<void> Function(WidgetRef ref, ScheduleColumn column, TimeObject block) deleteBlock; }`; `const dayScheduleBlockActions`; `showBlockEditModal({required BuildContext context, required ScheduleColumn column, required ScheduleBlockActions actions, required TimeObject block})` (was `date:`, no `actions:`); `BlockEditModal({required ScheduleColumn column, required ScheduleBlockActions actions, required TimeObject initialBlock})`.

Riverpod's `Ref` (used by `Notifier`s, e.g. `DragNotifier`) and `WidgetRef` (used by `ConsumerState`, e.g. `BlockEditModal`) are separate sealed types in `flutter_riverpod` 3.4.3 — neither is assignable to the other. `ScheduleController` (Task 2) is `Ref`-based because drag/resize live in `Notifier`s; `ScheduleBlockActions` here is `WidgetRef`-based because `BlockEditModal` is a widget. Don't try to unify them.

- [ ] **Step 1: Create `schedule_block_actions.dart`**

```dart
// lib/features/day/widgets/schedule_block_actions.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// The read/write operations [BlockEditModal] needs on the blocks
/// belonging to whichever [ScheduleColumn] it's editing, supplied by the
/// caller (`DayScreen` for a [DayColumn], `TemplatesScreen` for a
/// [TemplateColumn]) so this shared widget never imports either feature's
/// own providers directly.
class ScheduleBlockActions {
  const ScheduleBlockActions({
    required this.watchBlocks,
    required this.updateBlock,
    required this.deleteBlock,
  });

  /// Watches (reactively) the current blocks for [column], or `null`
  /// while still loading. Must be called from a widget's `build`, so
  /// implementations should `ref.watch`, not `ref.read`.
  final List<TimeObject>? Function(WidgetRef ref, ScheduleColumn column) watchBlocks;

  /// Updates [block] (which belongs to [column]), replacing any of
  /// [title]/[start]/[end]/[kind]/[categoryId] that are given.
  final Future<void> Function(
    WidgetRef ref,
    ScheduleColumn column,
    TimeObject block, {
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  })
  updateBlock;

  /// Removes [block] (which belongs to [column]).
  final Future<void> Function(WidgetRef ref, ScheduleColumn column, TimeObject block)
  deleteBlock;
}
```

- [ ] **Step 2: Create `day_schedule_block_actions.dart`**

```dart
// lib/features/day/day_schedule_block_actions.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/widgets/schedule_block_actions.dart';

DateTime _dateOf(ScheduleColumn column) => (column as DayColumn).date;

List<TimeObject>? _watchDayBlocks(WidgetRef ref, ScheduleColumn column) =>
    ref.watch(dayBlocksProvider(_dateOf(column))).value;

Future<void> _updateDayBlock(
  WidgetRef ref,
  ScheduleColumn column,
  TimeObject block, {
  String? title,
  DateTime? start,
  DateTime? end,
  BlockKind? kind,
  String? categoryId,
}) => ref
    .read(dayBlocksProvider(_dateOf(column)).notifier)
    .updateBlock(
      block,
      title: title,
      start: start,
      end: end,
      kind: kind,
      categoryId: categoryId,
    );

Future<void> _deleteDayBlock(
  WidgetRef ref,
  ScheduleColumn column,
  TimeObject block,
) => ref.read(dayBlocksProvider(_dateOf(column)).notifier).deleteBlock(block);

/// The [ScheduleBlockActions] `BlockEditModal` uses when editing a day
/// block. Every [ScheduleColumn] passed to it must be a [DayColumn].
const dayScheduleBlockActions = ScheduleBlockActions(
  watchBlocks: _watchDayBlocks,
  updateBlock: _updateDayBlock,
  deleteBlock: _deleteDayBlock,
);
```

- [ ] **Step 3: Edit `block_edit_modal.dart`'s imports, `showBlockEditModal`, and `BlockEditModal`'s fields**

Add imports:
```dart
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/widgets/schedule_block_actions.dart';
```

Replace `showBlockEditModal`:
```dart
/// Opens the block edit modal for [block] (which belongs to [column]):
/// title, start/end, and delete — plus, for a [DayColumn], copy-to-next-day
/// and a date row. Near-fullscreen on a narrow (mobile) width, a centered
/// fixed-width dialog on a wide one.
Future<void> showBlockEditModal({
  required BuildContext context,
  required ScheduleColumn column,
  required ScheduleBlockActions actions,
  required TimeObject block,
}) {
  if (isNarrow(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.95,
        child: BlockEditModal(column: column, actions: actions, initialBlock: block),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: BlockEditModal(column: column, actions: actions, initialBlock: block),
      ),
    ),
  );
}
```

Replace `BlockEditModal`'s class declaration:
```dart
class BlockEditModal extends ConsumerStatefulWidget {
  /// Creates a [BlockEditModal] for the block identified by
  /// [initialBlock]'s id, belonging to [column].
  const new({
    required this.column,
    required this.actions,
    required this.initialBlock,
    super.key,
  });

  /// The column [initialBlock] belongs to.
  final ScheduleColumn column;

  /// Reads/writes [initialBlock]'s title/category/kind/start/end/delete.
  final ScheduleBlockActions actions;

  /// The block as known when the modal was opened.
  final TimeObject initialBlock;

  @override
  ConsumerState<BlockEditModal> createState() => _BlockEditModalState();
}
```

- [ ] **Step 4: Edit `_BlockEditModalState`**

Replace `_currentDate` with `_currentColumn`:
```dart
  /// The column whose provider this modal currently watches/writes
  /// through. Starts at [BlockEditModal.column] (a `final` constructor
  /// param that can't itself change) and is reassigned by [_changeDate]
  /// after a cross-day move (day columns only), so the modal keeps
  /// showing the same block on its new date instead of the move looking
  /// like the block was deleted.
  late ScheduleColumn _currentColumn;
```
and in `initState`: `_currentColumn = widget.column;`.

Replace every method that used `dayBlocksProvider(_currentDate)`/`_currentDate` to instead go through `widget.actions`/`_currentColumn`, keeping `_changeDate`/`_copyToNextDay` (and the "canCopy"/date-row UI in `build()`) as day-only, gated on `widget.column is DayColumn`:

```dart
  Future<void> _commitTitle(TimeObject block) async {
    final value = _titleController.text.trim();
    if (value.isEmpty) {
      _titleController.text = block.title;
      return;
    }
    if (value != block.title) {
      await widget.actions.updateBlock(ref, _currentColumn, block, title: value);
    }
  }
```

`_toggleTimeField` is unchanged (doesn't touch providers).

```dart
  /// Opens the standard Material date picker and, if a different date is
  /// picked, moves [block] there directly via the day repository (this is
  /// only ever reachable when [widget.column] is a [DayColumn] — see the
  /// date row's guard in `build`) — the same move-and-refresh pattern
  /// `DragNotifier.drop` uses for a drag-and-drop move — then switches
  /// [_currentColumn] to the new date. Only the calendar itself closes;
  /// the modal stays open, now reading/writing through the new date's
  /// provider.
  Future<void> _changeDate(TimeObject block) async {
    await _commitTitle(block);
    if (!mounted) return;
    final currentDate = (_currentColumn as DayColumn).date;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(currentDate.year - 5),
      lastDate: DateTime(currentDate.year + 5),
    );
    if (picked == null || !mounted) return;

    final newDate = DateTime(picked.year, picked.month, picked.day);
    if (newDate == currentDate) return;

    final duration = block.end.difference(block.start);
    final newStart = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      block.start.hour,
      block.start.minute,
    );
    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.move(
      block,
      fromDate: currentDate,
      toDate: newDate,
      newStart: newStart,
      newEnd: newStart.add(duration),
    );

    ref.invalidate(dayBlocksProvider(currentDate));
    ref.invalidate(dayBlocksProvider(newDate));
    await ref.read(dayBlocksProvider(currentDate).future);
    await ref.read(dayBlocksProvider(newDate).future);
    if (!mounted) return;
    setState(() => _currentColumn = DayColumn(newDate));
  }

  Future<void> _confirmTime(TimeObject block, _TimeField field, DateTime picked) async {
    await widget.actions.updateBlock(
      ref,
      _currentColumn,
      block,
      start: field == _TimeField.start ? picked : null,
      end: field == _TimeField.end ? picked : null,
    );
  }

  Future<void> _setKind(TimeObject block, BlockKind kind) async {
    if (kind == block.kind) return;
    await widget.actions.updateBlock(ref, _currentColumn, block, kind: kind);
  }

  Future<void> _setCategory(TimeObject block, String categoryId) async {
    if (categoryId == block.categoryId) return;
    await widget.actions.updateBlock(ref, _currentColumn, block, categoryId: categoryId);
  }

  /// Copies [block] to the following calendar day. Only ever reachable
  /// when [widget.column] is a [DayColumn] — see the copy button's guard
  /// in `build`.
  Future<void> _copyToNextDay(TimeObject block) async {
    await _commitTitle(block);
    if (!mounted) return;
    final currentDate = (_currentColumn as DayColumn).date;
    final blocks = ref.read(dayBlocksProvider(currentDate)).value;
    final toCopy = blocks == null ? block : (_findById(blocks, block.id) ?? block);
    await ref.read(dayBlocksProvider(currentDate).notifier).copyToNextDay(toCopy);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied to next day')));
  }

  Future<void> _delete(TimeObject block) async {
    await widget.actions.deleteBlock(ref, _currentColumn, block);
    _currentBlock = null;
    if (mounted) Navigator.of(context).pop();
  }
```

`_findById` is unchanged.

- [ ] **Step 5: Edit `build()`**

Replace `final blocks = ref.watch(dayBlocksProvider(_currentDate)).value;` with `final blocks = widget.actions.watchBlocks(ref, _currentColumn);`.

Replace the `nextDate`/`nextDayBlocks`/`canCopy` block — only meaningful for a `DayColumn` — with:
```dart
    final settings = ref.watch(daySettingsProvider);
    final isDayColumn = widget.column is DayColumn;
    bool canCopy = false;
    if (isDayColumn) {
      final currentDate = (_currentColumn as DayColumn).date;
      final nextDate = DateTime(currentDate.year, currentDate.month, currentDate.day + 1);
      final nextDayBlocks = ref.watch(dayBlocksProvider(nextDate)).value;
      canCopy =
          nextDayBlocks != null &&
          !copyToNextDayWouldOverlap(
            block: current,
            nextDate: nextDate,
            nextDayBlocks: nextDayBlocks,
          );
    }
```
(insert this in place of the old `nextDate`/`nextDayBlocks`/`canCopy` computation, keeping `others` unchanged.)

Every `day: _currentDate` argument to `validEditRange` becomes `day: anchorDateFor(_currentColumn)` (needs `import 'package:taskframe/features/day/models/schedule_column.dart';`, already added in Step 3).

Wrap the date `ListTile` (`leading: Icon(Icons.calendar_today), ...`) in `if (isDayColumn) ...[ ListTile(...), ]` — it must not render for a `TemplateColumn`. Its own `Text(formatDate(_currentDate, settings.dateFormat))` becomes `Text(formatDate((_currentColumn as DayColumn).date, settings.dateFormat))`.

Change the trailing actions row's copy button:
```dart
                  IconButton(
                    tooltip: 'Copy to next day',
                    icon: const Icon(Icons.content_copy),
                    onPressed: isDayColumn && canCopy ? () => _copyToNextDay(current) : null,
                  ),
```
For a `TemplateColumn` this leaves the button always disabled rather than hidden — per the spec, "copy to next day" must be **omitted entirely**, not merely disabled, for a template block. Wrap it too: `if (isDayColumn) IconButton(...)`.

- [ ] **Step 6: Update `test/widget/block_edit_modal_test.dart`**

Add `import 'package:taskframe/features/day/day_schedule_block_actions.dart';` and `import 'package:taskframe/features/day/models/schedule_column.dart';`. Replace the one `showBlockEditModal(context: context, date: _date, block: block)` call with `showBlockEditModal(context: context, column: DayColumn(_date), actions: dayScheduleBlockActions, block: block)`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/widget/block_edit_modal_test.dart test/widget/day_grid_test.dart`
Expected: PASS (Task 6's `day_grid_test.dart` edits now resolve too, since `schedule_block_actions.dart`/`day_schedule_block_actions.dart` exist).

Run: `flutter analyze`
Expected: remaining errors only in `day_screen.dart` (Task 8).

- [ ] **Step 8: Commit**

```bash
git add lib/features/day/widgets/schedule_block_actions.dart lib/features/day/day_schedule_block_actions.dart lib/features/day/widgets/block_edit_modal.dart test/widget/block_edit_modal_test.dart
git commit -m "refactor: generalize BlockEditModal to ScheduleColumn/ScheduleBlockActions"
```

---

### Task 8: Update `DayScreen` (regression checkpoint)

**Files:**
- Modify: `lib/features/day/day_screen.dart`
- Modify: `test/widget/day_screen_test.dart` (only if any assertion touches internals changed above — expected to need none, since `DayScreen`'s public behavior is unchanged; verify by running first)

**Interfaces:**
- Consumes: `DayColumn`, `DayScheduleController`, `dayScheduleBlockActions` (Tasks 1, 2, 7).

- [ ] **Step 1: Add imports**

```dart
import 'package:taskframe/features/day/day_schedule_block_actions.dart';
import 'package:taskframe/features/day/day_schedule_controller.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
```

- [ ] **Step 2: Update the one `DayGrid(...)` construction in `_SchedulePage._buildColumn`**

```dart
        data: (blocks) => DayGrid(
          key: scheduleGridKeyFor(DayColumn(date)),
          date: date,
          column: DayColumn(date),
          controller: const DayScheduleController(),
          actions: dayScheduleBlockActions,
          blocks: blocks,
          settings: settings,
          slotHeight: slotHeight,
          showHourLabels: _showHourLabels,
          ...
```
(add `import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';` for `scheduleGridKeyFor` if not already imported — check first; `day_grid.dart` itself doesn't re-export it. `DayGrid` previously had no explicit `key:` here — `dayGridKeyFor`/now `scheduleGridKeyFor` was called from inside `DayGrid`'s own build via `_DraggableBlockState._updateResize`, not passed in as the widget's own `key:`. Confirm by re-reading the current `_buildColumn` before editing: if there is no existing `key:` argument on this `DayGrid(...)`, do **not** add one — only add `column`/`controller`/`actions`, leaving the widget's own `key` absent exactly as it is today.)

- [ ] **Step 3: Update the two `showBlockEditModal(...)` call sites** (`_createViaButton` and `_SchedulePage._createAndOpen`)

Both currently pass `date: date`; change to `column: DayColumn(date), actions: dayScheduleBlockActions,`.

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: PASS, with **zero** changes needed to `test/widget/day_screen_test.dart` — this is the regression check confirming Day behavior is unchanged after the whole generalization (Tasks 3–8). If any `day_screen_test.dart` assertion fails, that's a real regression to fix here, not a test to loosen.

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/day_screen.dart
git commit -m "refactor: wire DayScreen through DayColumn/DayScheduleController"
```

---

### Task 9: `Template` model + repository

**Files:**
- Create: `lib/features/template/models/template.dart`
- Create: `lib/features/template/data/template_repository.dart`
- Test: `test/unit/template_test.dart`
- Test: `test/unit/template_repository_test.dart`

**Interfaces:**
- Consumes: `TimeObject`, `BlockKind` (`lib/features/day/models/time_object.dart`, unchanged); `Category` (`lib/features/category/models/category.dart`, unchanged).
- Produces: `class Template { final String id; final String name; Template copyWith({String? name}); }`; `abstract class TemplateRepository { Future<List<Template>> load(); Future<Template> add({required String name}); Future<Template> rename(Template template, {required String name}); Future<void> delete(Template template); }`, `class InMemoryTemplateRepository implements TemplateRepository`; `abstract class TemplateBlocksRepository { Future<List<TimeObject>> load(String templateId); Future<TimeObject> add(String templateId, {required DateTime start, required DateTime end, required BlockKind kind, String? title, String? categoryId}); Future<TimeObject> move(TimeObject block, {required String fromTemplateId, required String toTemplateId, required DateTime newStart, required DateTime newEnd}); Future<TimeObject> update(TimeObject block, {required String templateId, String? title, DateTime? start, DateTime? end, BlockKind? kind, String? categoryId}); Future<void> delete(TimeObject block, {required String templateId}); }`, `class InMemoryTemplateBlocksRepository implements TemplateBlocksRepository`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/unit/template_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/template/models/template.dart';

void main() {
  group('Template', () {
    test('copyWith replaces name and keeps id', () {
      const template = Template(id: 't1', name: 'Weekday');
      final renamed = template.copyWith(name: 'Weekend');
      expect(renamed.id, 't1');
      expect(renamed.name, 'Weekend');
    });

    test('copyWith with no arguments keeps the same name', () {
      const template = Template(id: 't1', name: 'Weekday');
      expect(template.copyWith().name, 'Weekday');
    });
  });
}
```

```dart
// test/unit/template_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/template/data/template_repository.dart';

void main() {
  group('InMemoryTemplateRepository', () {
    test('load starts empty', () async {
      final repository = InMemoryTemplateRepository();
      expect(await repository.load(), isEmpty);
    });

    test('add appends a template with the given name', () async {
      final repository = InMemoryTemplateRepository();
      final added = await repository.add(name: 'Weekday');
      expect(added.name, 'Weekday');
      expect(await repository.load(), [added]);
    });

    test('rename updates the template\'s name', () async {
      final repository = InMemoryTemplateRepository();
      final added = await repository.add(name: 'Weekday');
      final renamed = await repository.rename(added, name: 'Renamed');
      expect(renamed.id, added.id);
      expect((await repository.load()).single.name, 'Renamed');
    });

    test('delete removes the template', () async {
      final repository = InMemoryTemplateRepository();
      final added = await repository.add(name: 'Weekday');
      await repository.delete(added);
      expect(await repository.load(), isEmpty);
    });

    test('add assigns distinct ids to successive templates', () async {
      final repository = InMemoryTemplateRepository();
      final first = await repository.add(name: 'A');
      final second = await repository.add(name: 'B');
      expect(first.id, isNot(second.id));
    });
  });

  group('InMemoryTemplateBlocksRepository', () {
    test('load starts empty for a fresh templateId', () async {
      final repository = InMemoryTemplateBlocksRepository();
      expect(await repository.load('t1'), isEmpty);
    });

    test('add appends a block for the given templateId', () async {
      final repository = InMemoryTemplateBlocksRepository();
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
        title: 'Standup',
      );
      expect(added.title, 'Standup');
      final blocks = await repository.load('t1');
      expect(blocks.single.id, added.id);
    });

    test('a block added to one templateId is invisible to another', () async {
      final repository = InMemoryTemplateBlocksRepository();
      await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );
      expect(await repository.load('t2'), isEmpty);
    });

    test('move moves a block from one templateId to another', () async {
      final repository = InMemoryTemplateBlocksRepository();
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      await repository.move(
        added,
        fromTemplateId: 't1',
        toTemplateId: 't2',
        newStart: DateTime(2000, 1, 1, 14),
        newEnd: DateTime(2000, 1, 1, 14, 30),
      );

      expect(await repository.load('t1'), isEmpty);
      final moved = (await repository.load('t2')).single;
      expect(moved.id, added.id);
      expect(moved.start, DateTime(2000, 1, 1, 14));
    });

    test('update persists a title change', () async {
      final repository = InMemoryTemplateBlocksRepository();
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      await repository.update(added, templateId: 't1', title: 'Renamed');

      final updated = (await repository.load('t1')).single;
      expect(updated.title, 'Renamed');
    });

    test('delete removes the block', () async {
      final repository = InMemoryTemplateBlocksRepository();
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      await repository.delete(added, templateId: 't1');

      expect(await repository.load('t1'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/unit/template_test.dart test/unit/template_repository_test.dart`
Expected: FAIL — neither file exists yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/template/models/template.dart

/// One template: a named, reusable set of events, editable with the same
/// schedule UI a real day uses (see `TemplatesScreen`).
class Template {
  const Template({required this.id, required this.name});

  /// Unique identifier for this template — also its `TemplateColumn.
  /// templateId`.
  final String id;

  /// Display name, shown as this template's column header.
  final String name;

  /// Returns a copy of this template with [name] replaced.
  Template copyWith({String? name}) => Template(id: id, name: name ?? this.name);

  @override
  bool operator ==(Object other) =>
      other is Template && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
```

```dart
// lib/features/template/data/template_repository.dart
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/template/models/template.dart';

/// Loads and stores the list of templates.
abstract class TemplateRepository {
  /// Returns every template, in creation order.
  Future<List<Template>> load();

  /// Creates a new template named [name] and returns it.
  Future<Template> add({required String name});

  /// Renames [template] to [name] and returns the updated template.
  Future<Template> rename(Template template, {required String name});

  /// Removes [template].
  Future<void> delete(Template template);
}

/// A [TemplateRepository] that keeps templates in memory for the life of
/// the app, starting empty.
class InMemoryTemplateRepository implements TemplateRepository {
  final List<Template> _templates = [];
  int _nextId = 0;

  @override
  Future<List<Template>> load() async => List.unmodifiable(_templates);

  @override
  Future<Template> add({required String name}) async {
    final template = Template(id: 'template-${_nextId++}', name: name);
    _templates.add(template);
    return template;
  }

  @override
  Future<Template> rename(Template template, {required String name}) async {
    final renamed = template.copyWith(name: name);
    final index = _templates.indexWhere((t) => t.id == template.id);
    _templates[index] = renamed;
    return renamed;
  }

  @override
  Future<void> delete(Template template) async {
    _templates.removeWhere((t) => t.id == template.id);
  }
}

/// Loads and stores the timeline blocks for a given template, mirroring
/// `DayBlocksRepository`'s shape but keyed by `templateId` instead of a
/// calendar date, with no seed data and no day-only "copy to next day"
/// equivalent.
abstract class TemplateBlocksRepository {
  /// Returns the blocks for [templateId].
  Future<List<TimeObject>> load(String templateId);

  /// Creates a new block on [templateId] and returns it. [title] defaults
  /// to a placeholder when omitted.
  Future<TimeObject> add(
    String templateId, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  });

  /// Moves [block] from [fromTemplateId] to [toTemplateId], updating its
  /// start/end to [newStart]/[newEnd], and returns the updated block.
  /// [fromTemplateId] and [toTemplateId] may be the same id.
  Future<TimeObject> move(
    TimeObject block, {
    required String fromTemplateId,
    required String toTemplateId,
    required DateTime newStart,
    required DateTime newEnd,
  });

  /// Updates [block] (which belongs to [templateId]) in place, replacing
  /// any of [title]/[start]/[end]/[kind]/[categoryId] that are given.
  /// Returns the updated block.
  Future<TimeObject> update(
    TimeObject block, {
    required String templateId,
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  });

  /// Removes [block] (which belongs to [templateId]).
  Future<void> delete(TimeObject block, {required String templateId});
}

/// A [TemplateBlocksRepository] that keeps blocks in memory for the life
/// of the app, starting empty for every template.
class InMemoryTemplateBlocksRepository implements TemplateBlocksRepository {
  final Map<String, List<TimeObject>> _blocks = {};
  int _nextId = 0;

  @override
  Future<List<TimeObject>> load(String templateId) async =>
      [...?_blocks[templateId]];

  @override
  Future<TimeObject> add(
    String templateId, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  }) async {
    final block = TimeObject(
      id: 'template-block-${_nextId++}',
      title: title ?? 'title',
      start: start,
      end: end,
      kind: kind,
      locked: false,
      categoryId: categoryId ?? Category.defaultId,
    );
    _blocks[templateId] = [...?_blocks[templateId], block];
    return block;
  }

  @override
  Future<TimeObject> move(
    TimeObject block, {
    required String fromTemplateId,
    required String toTemplateId,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final fromList = _blocks[fromTemplateId];
    if (fromList != null) {
      _blocks[fromTemplateId] = fromList.where((b) => b.id != block.id).toList();
    }

    final moved = TimeObject(
      id: block.id,
      title: block.title,
      start: newStart,
      end: newEnd,
      kind: block.kind,
      locked: block.locked,
      categoryId: block.categoryId,
    );
    _blocks[toTemplateId] = [...?_blocks[toTemplateId], moved];
    return moved;
  }

  @override
  Future<TimeObject> update(
    TimeObject block, {
    required String templateId,
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  }) async {
    final updated = TimeObject(
      id: block.id,
      title: title ?? block.title,
      start: start ?? block.start,
      end: end ?? block.end,
      kind: kind ?? block.kind,
      locked: block.locked,
      categoryId: categoryId ?? block.categoryId,
    );
    final list = _blocks[templateId] ?? [];
    _blocks[templateId] = [
      for (final b in list)
        if (b.id == block.id) updated else b,
    ];
    return updated;
  }

  @override
  Future<void> delete(TimeObject block, {required String templateId}) async {
    final list = _blocks[templateId];
    if (list != null) {
      _blocks[templateId] = list.where((b) => b.id != block.id).toList();
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/template_test.dart test/unit/template_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/template/models/template.dart lib/features/template/data/template_repository.dart test/unit/template_test.dart test/unit/template_repository_test.dart
git commit -m "feat: add Template model and in-memory repositories"
```

---

### Task 10: Template providers

**Files:**
- Create: `lib/features/template/providers.dart`
- Test: `test/unit/template_providers_test.dart`

**Interfaces:**
- Consumes: `Template`, `TemplateRepository`, `InMemoryTemplateRepository`, `TemplateBlocksRepository`, `InMemoryTemplateBlocksRepository` (Task 9); `ScheduleColumn`, `TemplateColumn` (Task 1); `ScheduleController` (Task 2); `ScheduleBlockActions` (Task 7); `isValidBlockEdit`, `TimeObject`, `BlockKind` (existing day feature files, unchanged).
- Produces: `templateRepositoryProvider`, `templateListProvider` (`AsyncNotifierProvider<TemplateListNotifier, List<Template>>` with `addTemplate({required String name})`, `renameTemplate(Template, {required String name})`, `deleteTemplate(Template)`); `templateBlocksRepositoryProvider`; `templateBlocksProvider` (`AsyncNotifierProvider.family<TemplateBlocksNotifier, List<TimeObject>, String>` with `addBlock`/`updateBlock`/`deleteBlock`, same signatures as `DayBlocksNotifier`'s minus `copyToNextDay`); `class TemplateScheduleController extends ScheduleController`; `const templateScheduleBlockActions`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/template_providers_test.dart
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
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/template_providers_test.dart`
Expected: FAIL — `lib/features/template/providers.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/template/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
import 'package:taskframe/features/day/widgets/schedule_block_actions.dart';
import 'package:taskframe/features/template/data/template_repository.dart';
import 'package:taskframe/features/template/models/template.dart';

/// The backing store for templates. Overriding this single provider is
/// enough to change where templates are loaded from and saved to.
final templateRepositoryProvider = Provider<TemplateRepository>(
  (ref) => InMemoryTemplateRepository(),
);

/// Holds the list of templates, loaded from [templateRepositoryProvider],
/// and lets consumers add/rename/delete them.
class TemplateListNotifier extends AsyncNotifier<List<Template>> {
  @override
  Future<List<Template>> build() => ref.watch(templateRepositoryProvider).load();

  /// Creates a new template named [name], adds it to the current state,
  /// and returns it.
  Future<Template> addTemplate({required String name}) async {
    final repository = ref.read(templateRepositoryProvider);
    final added = await repository.add(name: name);
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Renames [template] to [name], persisting via the repository and
  /// refreshing state.
  Future<void> renameTemplate(Template template, {required String name}) async {
    final repository = ref.read(templateRepositoryProvider);
    final renamed = await repository.rename(template, name: name);
    state = AsyncData([
      for (final t in state.value ?? <Template>[])
        if (t.id == template.id) renamed else t,
    ]);
  }

  /// Removes [template], persisting via the repository and refreshing
  /// state.
  Future<void> deleteTemplate(Template template) async {
    final repository = ref.read(templateRepositoryProvider);
    await repository.delete(template);
    state = AsyncData([
      for (final t in state.value ?? <Template>[])
        if (t.id != template.id) t,
    ]);
  }
}

/// The list of templates.
final templateListProvider =
    AsyncNotifierProvider<TemplateListNotifier, List<Template>>(
      TemplateListNotifier.new,
    );

/// The backing store for template blocks.
final templateBlocksRepositoryProvider = Provider<TemplateBlocksRepository>(
  (ref) => InMemoryTemplateBlocksRepository(),
);

/// Holds the timeline blocks for one template, loaded from
/// [templateBlocksRepositoryProvider], and lets a `TemplatesScreen` add
/// new ones — mirrors `DayBlocksNotifier`, minus `copyToNextDay`, which
/// has no template equivalent.
class TemplateBlocksNotifier extends AsyncNotifier<List<TimeObject>> {
  TemplateBlocksNotifier(this.templateId);

  /// The template these blocks belong to.
  final String templateId;

  @override
  Future<List<TimeObject>> build() =>
      ref.watch(templateBlocksRepositoryProvider).load(templateId);

  Future<TimeObject> addBlock({
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  }) async {
    final repository = ref.read(templateBlocksRepositoryProvider);
    final added = await repository.add(
      templateId,
      start: start,
      end: end,
      kind: kind,
      title: title,
      categoryId: categoryId,
    );
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Updates [block]'s title/start/end/kind, persisting via the
  /// repository and refreshing state. Silently does nothing if the
  /// resulting start/end would be invalid (see [isValidBlockEdit]).
  Future<void> updateBlock(
    TimeObject block, {
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  }) async {
    final newStart = start ?? block.start;
    final newEnd = end ?? block.end;
    final others = (state.value ?? []).where((b) => b.id != block.id).toList();
    final settings = ref.read(daySettingsProvider);
    if (!isValidBlockEdit(
      start: newStart,
      end: newEnd,
      settings: settings,
      day: templateAnchorDate,
      others: others,
    )) {
      return;
    }

    final repository = ref.read(templateBlocksRepositoryProvider);
    final updated = await repository.update(
      block,
      templateId: templateId,
      title: title,
      start: start,
      end: end,
      kind: kind,
      categoryId: categoryId,
    );
    state = AsyncData([
      for (final b in state.value ?? <TimeObject>[])
        if (b.id == block.id) updated else b,
    ]);
  }

  Future<void> deleteBlock(TimeObject block) async {
    final repository = ref.read(templateBlocksRepositoryProvider);
    await repository.delete(block, templateId: templateId);
    state = AsyncData([
      for (final b in state.value ?? <TimeObject>[])
        if (b.id != block.id) b,
    ]);
  }
}

/// The timeline blocks for a given template.
final templateBlocksProvider =
    AsyncNotifierProvider.family<TemplateBlocksNotifier, List<TimeObject>, String>(
      TemplateBlocksNotifier.new,
    );

/// A [ScheduleController] backed by [templateBlocksProvider]/
/// [templateBlocksRepositoryProvider]. Every [ScheduleColumn] it's given
/// must be a [TemplateColumn].
class TemplateScheduleController extends ScheduleController {
  const TemplateScheduleController();

  String _idOf(ScheduleColumn column) => (column as TemplateColumn).templateId;

  @override
  List<TimeObject>? blocksOf(Ref ref, ScheduleColumn column) =>
      ref.read(templateBlocksProvider(_idOf(column))).value;

  @override
  Future<void> moveBlock(
    Ref ref, {
    required TimeObject block,
    required ScheduleColumn fromColumn,
    required ScheduleColumn toColumn,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final fromId = _idOf(fromColumn);
    final toId = _idOf(toColumn);
    final repository = ref.read(templateBlocksRepositoryProvider);
    await repository.move(
      block,
      fromTemplateId: fromId,
      toTemplateId: toId,
      newStart: newStart,
      newEnd: newEnd,
    );
    ref.invalidate(templateBlocksProvider(fromId));
    ref.invalidate(templateBlocksProvider(toId));
    await ref.read(templateBlocksProvider(fromId).future);
    await ref.read(templateBlocksProvider(toId).future);
  }
}

String _idOfColumn(ScheduleColumn column) => (column as TemplateColumn).templateId;

List<TimeObject>? _watchTemplateBlocks(WidgetRef ref, ScheduleColumn column) =>
    ref.watch(templateBlocksProvider(_idOfColumn(column))).value;

Future<void> _updateTemplateBlock(
  WidgetRef ref,
  ScheduleColumn column,
  TimeObject block, {
  String? title,
  DateTime? start,
  DateTime? end,
  BlockKind? kind,
  String? categoryId,
}) => ref
    .read(templateBlocksProvider(_idOfColumn(column)).notifier)
    .updateBlock(
      block,
      title: title,
      start: start,
      end: end,
      kind: kind,
      categoryId: categoryId,
    );

Future<void> _deleteTemplateBlock(
  WidgetRef ref,
  ScheduleColumn column,
  TimeObject block,
) => ref.read(templateBlocksProvider(_idOfColumn(column)).notifier).deleteBlock(block);

/// The [ScheduleBlockActions] `BlockEditModal` uses when editing a
/// template block. Every [ScheduleColumn] passed to it must be a
/// [TemplateColumn].
const templateScheduleBlockActions = ScheduleBlockActions(
  watchBlocks: _watchTemplateBlocks,
  updateBlock: _updateTemplateBlock,
  deleteBlock: _deleteTemplateBlock,
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/template_providers_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/template/providers.dart test/unit/template_providers_test.dart
git commit -m "feat: add template providers, TemplateScheduleController, templateScheduleBlockActions"
```

---

### Task 11: `TemplatesScreen`

**Files:**
- Create: `lib/features/template/widgets/templates_screen.dart`
- Test: `test/widget/templates_screen_test.dart`

**Interfaces:**
- Consumes: `templateListProvider`, `templateBlocksProvider`, `TemplateScheduleController`, `templateScheduleBlockActions` (Task 10); `TemplateColumn`, `templateAnchorDate` (Task 1); `DayGrid`, `showBlockEditModal` (day feature, unchanged since Tasks 6–7); `daySettingsProvider`, `resolveSlotHeight`, `HourGutter`, `isNarrow` (existing, unchanged).

`TemplatesScreen` mirrors `DayScreen`'s structure closely (page/column shell, narrow-vs-wide split) but is deliberately **not** built by extracting a shared base class from `DayScreen` — the spec calls for reusing the grid/drag/resize/edit-modal *machinery*, not the page-level swipe/paging widget itself, and `DayScreen`'s paging is date-arithmetic-specific (`_startDateForPage`, `_pageSpread`) in a way that doesn't carry over to an ordered template list. Keep this file self-contained; do not attempt to share `_DayScreenState` code with it.

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/templates_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/template/widgets/templates_screen.dart';

void _resizeViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: TemplatesScreen())),
  );
  await tester.pump();
}

void main() {
  group('TemplatesScreen', () {
    testWidgets('starts with no templates and an add button', (tester) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);

      expect(find.widgetWithText(AppBar, 'Templates'), findsOneWidget);
      expect(find.byTooltip('Add template'), findsOneWidget);
    });

    testWidgets('the add button creates a template named "Template 1"', (tester) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);

      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();

      expect(find.text('Template 1'), findsOneWidget);
    });

    testWidgets('a second added template is named "Template 2"', (tester) async {
      _resizeViewport(tester, const Size(1200, 1000));
      await _pump(tester);

      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();

      expect(find.text('Template 1'), findsOneWidget);
      expect(find.text('Template 2'), findsOneWidget);
    });

    testWidgets('the delete action on a column removes that template', (tester) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);
      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete template'));
      await tester.pumpAndSettle();

      expect(find.text('Template 1'), findsNothing);
      expect(find.byTooltip('Add template'), findsOneWidget);
    });

    testWidgets(
      'on a narrow width, adding two templates pages to the second '
      'with the next-template arrow',
      (tester) async {
        _resizeViewport(tester, const Size(500, 1000));
        await _pump(tester);
        await tester.tap(find.byTooltip('Add template'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Add template'));
        await tester.pumpAndSettle();
        // Adding opens straight to the new template, so we're on
        // "Template 2"; page back to confirm "Template 1" is reachable.
        expect(find.byTooltip('Previous template'), findsOneWidget);

        await tester.tap(find.byTooltip('Previous template'));
        await tester.pumpAndSettle();

        expect(find.text('Template 1'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping a column opens the block edit modal without a date row or '
      'copy button',
      (tester) async {
        _resizeViewport(tester, const Size(800, 1000));
        await _pump(tester);
        await tester.tap(find.byTooltip('Add template'));
        await tester.pumpAndSettle();

        await tester.longPressAt(const Offset(200, 300));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.event), findsWidgets); // draft overlay open
        // Tapping the anchor/frame draft button opens the edit modal;
        // exact offsets mirror day_screen_test.dart's own long-press draft
        // pattern — adjust the tap target to whichever draft button lands
        // under the long-press in the actual layout if this differs from
        // day_grid_test.dart's DraftOverlay expectations.
      },
    );
  });
}
```

(The final test is intentionally sketched loosely — before implementing, check `test/widget/day_grid_test.dart`'s existing long-press-to-draft-to-edit-modal test for the exact tap sequence used there, and mirror it precisely rather than guessing offsets; then assert `find.byIcon(Icons.calendar_today)` (the date row's leading icon) and `find.byTooltip('Copy to next day')` both `findsNothing` once the modal is open.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/templates_screen_test.dart`
Expected: FAIL — `templates_screen.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/template/widgets/templates_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/day_grid_sizing.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/hour_gutter.dart';
import 'package:taskframe/features/template/models/template.dart';
import 'package:taskframe/features/template/providers.dart';

const _minSlotHeight = 8.0;
const _headerHeight = 56.0;
const _columnGap = 8.0;
const _newBlockDuration = Duration(minutes: 60);

/// The templates screen: a set of named templates, each with its own
/// full schedule editor reusing `DayGrid`. Narrow widths show one
/// template per page (swipe/arrows between templates); wide widths show
/// every template as a side-by-side column.
class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  int _pageIndex = 0;

  Future<void> _addTemplate() async {
    final templates = ref.read(templateListProvider).value ?? const [];
    final name = 'Template ${templates.length + 1}';
    await ref.read(templateListProvider.notifier).addTemplate(name: name);
    setState(() => _pageIndex = templates.length);
  }

  Future<void> _deleteTemplate(Template template) async {
    final templates = ref.read(templateListProvider).value ?? const [];
    await ref.read(templateListProvider.notifier).deleteTemplate(template);
    final remaining = templates.length - 1;
    if (_pageIndex >= remaining && remaining > 0) {
      setState(() => _pageIndex = remaining - 1);
    } else if (remaining == 0) {
      setState(() => _pageIndex = 0);
    }
  }

  Future<void> _createViaButton(BuildContext context, Template template) async {
    final settings = ref.read(daySettingsProvider);
    final existingBlocks = ref.read(templateBlocksProvider(template.id)).value ?? [];
    final start = findNextFreeSlot(
      day: templateAnchorDate,
      existingBlocks: existingBlocks,
      settings: settings,
      duration: _newBlockDuration,
    );
    final end = dayEndFor(templateAnchorDate, settings).isBefore(start.add(_newBlockDuration))
        ? dayEndFor(templateAnchorDate, settings)
        : start.add(_newBlockDuration);

    final created = await ref
        .read(templateBlocksProvider(template.id).notifier)
        .addBlock(start: start, end: end, kind: BlockKind.anchor);
    if (!context.mounted) return;
    await showBlockEditModal(
      context: context,
      column: TemplateColumn(template.id),
      actions: templateScheduleBlockActions,
      block: created,
    );
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templateListProvider);
    final templates = templatesAsync.value ?? const <Template>[];
    final narrow = isNarrow(context);
    final currentIndex = templates.isEmpty
        ? 0
        : _pageIndex.clamp(0, templates.length - 1);

    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox(),
        title: const Text('Templates'),
        actions: [
          IconButton(
            tooltip: 'Add template',
            icon: const Icon(Icons.add),
            onPressed: () => unawaited(_addTemplate()),
          ),
        ],
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load: $error')),
        data: (_) {
          if (templates.isEmpty) {
            return const Center(child: Text('No templates yet'));
          }
          final visible = narrow ? [templates[currentIndex]] : templates;
          return Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    SizedBox(
                      height: _headerHeight,
                      child: Row(
                        children: [
                          const SizedBox(width: HourGutter.width),
                          for (var i = 0; i < visible.length; i++) ...[
                            if (i > 0)
                              const VerticalDivider(width: _columnGap, thickness: 1),
                            Expanded(child: _ColumnHeader(
                              template: visible[i],
                              onDelete: () => unawaited(_deleteTemplate(visible[i])),
                            )),
                          ],
                          const SizedBox(width: HourGutter.width),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final settings = ref.watch(daySettingsProvider);
                          final slotCount =
                              (settings.dayEndHour - settings.dayStartHour) * 4;
                          final slotHeight = resolveSlotHeight(
                            availableHeight: constraints.maxHeight,
                            slotCount: slotCount,
                            minSlotHeight: _minSlotHeight,
                          );
                          return SingleChildScrollView(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                HourGutter(settings: settings, slotHeight: slotHeight),
                                for (var i = 0; i < visible.length; i++) ...[
                                  if (i > 0) const SizedBox(width: _columnGap),
                                  Expanded(
                                    child: _TemplateColumnGrid(
                                      template: visible[i],
                                      settings: settings,
                                      slotHeight: slotHeight,
                                      onCreateViaButton: () =>
                                          unawaited(_createViaButton(context, visible[i])),
                                    ),
                                  ),
                                ],
                                HourGutter(settings: settings, slotHeight: slotHeight),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (narrow && templates.length > 1) ...[
                Positioned(
                  top: 0,
                  left: 8,
                  height: _headerHeight,
                  child: IconButton(
                    tooltip: 'Previous template',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: currentIndex > 0
                        ? () => setState(() => _pageIndex = currentIndex - 1)
                        : null,
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 8,
                  height: _headerHeight,
                  child: IconButton(
                    tooltip: 'Next template',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: currentIndex < templates.length - 1
                        ? () => setState(() => _pageIndex = currentIndex + 1)
                        : null,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ColumnHeader extends StatefulWidget {
  const _ColumnHeader({required this.template, required this.onDelete});

  final Template template;
  final VoidCallback onDelete;

  @override
  State<_ColumnHeader> createState() => _ColumnHeaderState();
}

class _ColumnHeaderState extends State<_ColumnHeader> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.template.name);
  }

  @override
  void didUpdateWidget(_ColumnHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template.name != widget.template.name) {
      _controller.text = widget.template.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isNotEmpty && trimmed != widget.template.name) {
                  unawaited(
                    ref
                        .read(templateListProvider.notifier)
                        .renameTemplate(widget.template, name: trimmed),
                  );
                }
              },
            ),
          ),
          IconButton(
            tooltip: 'Delete template',
            icon: const Icon(Icons.delete_outline),
            visualDensity: VisualDensity.compact,
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

class _TemplateColumnGrid extends ConsumerWidget {
  const _TemplateColumnGrid({
    required this.template,
    required this.settings,
    required this.slotHeight,
    required this.onCreateViaButton,
  });

  final Template template;
  final DaySettings settings;
  final double slotHeight;
  final VoidCallback onCreateViaButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocksAsync = ref.watch(templateBlocksProvider(template.id));
    return blocksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Failed to load: $error')),
      data: (blocks) => DayGrid(
        date: templateAnchorDate,
        column: TemplateColumn(template.id),
        controller: const TemplateScheduleController(),
        actions: templateScheduleBlockActions,
        blocks: blocks,
        settings: settings,
        slotHeight: slotHeight,
        showHourLabels: false,
        onCreateBlock: ({required start, required end, required kind}) {
          unawaited(
            ref
                .read(templateBlocksProvider(template.id).notifier)
                .addBlock(start: start, end: end, kind: kind)
                .then((created) => showBlockEditModal(
                      context: context,
                      column: TemplateColumn(template.id),
                      actions: templateScheduleBlockActions,
                      block: created,
                    )),
          );
        },
      ),
    );
  }
}
```

Adjust `import 'package:taskframe/features/day/day_new_block.dart';` for `BlockKind` — it's actually defined in `models/time_object.dart`, already imported above; drop the unused re-import if `flutter analyze` flags it after writing.

- [ ] **Step 4: Run test, fix compile/behavior issues, until it passes**

Run: `flutter test test/widget/templates_screen_test.dart`
Expected: PASS. Iterate: this is the first task assembling a brand-new screen from many pieces, so expect at least one or two rounds of fixing widget-tree/finder mismatches (e.g. tooltip text, exact tap coordinates for the long-press draft test) before it's green — check actual widget output with `tester.pumpWidget` + debugging (`debugDumpApp()` or comparing against `day_screen_test.dart`'s own long-press pattern) rather than guessing repeatedly.

- [ ] **Step 5: Commit**

```bash
git add lib/features/template/widgets/templates_screen.dart test/widget/templates_screen_test.dart
git commit -m "feat: add TemplatesScreen"
```

---

### Task 12: Router + `AppShell` wiring

**Files:**
- Modify: `lib/router.dart`
- Modify: `lib/core/widgets/app_shell.dart`
- Modify: `test/widget/router_test.dart`
- Modify: `test/widget/app_shell_test.dart`

**Interfaces:**
- Consumes: `TemplatesScreen` (Task 11).

- [ ] **Step 1: Add the `/templates` branch to `router.dart`**

```dart
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/widgets/app_shell.dart';
import 'package:taskframe/features/category/widgets/categories_screen.dart';
import 'package:taskframe/features/day/day_screen.dart';
import 'package:taskframe/features/template/widgets/templates_screen.dart';

/// Application router: a shell with three branches (Day/Week, Templates,
/// Categories), each keeping its own state alive when the others are
/// shown.
final GoRouter appRouter = GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const DayScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/templates',
              builder: (context, state) => const TemplatesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/categories',
              builder: (context, state) => const CategoriesScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
```

(Templates placed as the middle branch, between Day and Categories, matching branch order to nav order in Step 2.)

- [ ] **Step 2: Add the "Templates" destination to `app_shell.dart`**

```dart
const _destinations = [
  _Destination(icon: Icons.calendar_today, label: 'Day'),
  _Destination(icon: Icons.dashboard_customize, label: 'Templates'),
  _Destination(icon: Icons.category, label: 'Categories'),
];
```

(Nothing else in `app_shell.dart` references destinations by index in a way that needs updating — `_drawerDestinations()` and both the narrow/wide `build()` branches already iterate `_destinations` generically.)

- [ ] **Step 3: Update `test/widget/router_test.dart`**

Read the file first (`grep -n "Categories\|/categories\|DayScreen\|currentIndex" test/widget/router_test.dart`) to find assertions keyed to branch index or count (e.g. "there are 2 branches", or navigating to index 1 expects Categories). Update any such assertion for the new 3-branch order (index 0 = Day, 1 = Templates, 2 = Categories), and add a new test analogous to the existing Day/Categories navigation test, confirming tapping/selecting the Templates destination shows `TemplatesScreen`'s app bar title ("Templates").

- [ ] **Step 4: Update `test/widget/app_shell_test.dart`**

Read the file first (`grep -n "_destinations\|Day\|Categories\|selectedIndex\|length" test/widget/app_shell_test.dart`). Update any assertion counting exactly 2 destinations to 3, and any assertion checking destination order/labels to include "Templates" between "Day" and "Categories".

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/widget/router_test.dart test/widget/app_shell_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/router.dart lib/core/widgets/app_shell.dart test/widget/router_test.dart test/widget/app_shell_test.dart
git commit -m "feat: wire TemplatesScreen into the router and nav shell"
```

---

### Task 13: Full regression run

**Files:** none (verification only).

- [ ] **Step 1: Run the entire test suite**

Run: `flutter test`
Expected: PASS, all files.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: no errors (pre-existing lint warnings unrelated to this work, if any, are out of scope to fix here).

- [ ] **Step 3: Manual smoke check**

Start the app per the project's existing manual-verification workflow (the `run` skill / dev-server-on-port-8080 convention already used in this project), navigate to Templates, add two templates, add a block to each via long-press, drag a block from one template column to another (wide width), resize a block, edit its title/category, open its edit modal and confirm there is no date row and no copy-to-next-day button, then delete a template. Confirm Day screen behavior (add/drag/resize/copy-to-next-day/date-change) is unaffected.

- [ ] **Step 4: Final commit (only if smoke-check fixes were needed)**

```bash
git add -A
git commit -m "fix: address issues found in event-templates regression pass"
```

---

## Self-Review Notes

- **Spec coverage:** Template model/repository (Task 9) ✓; `ScheduleColumn`/reuse of grid+drag+resize+edit-modal (Tasks 1–8) ✓; `/templates` route + nav entry (Task 12) ✓; add/remove templates with a `+` button and per-column delete (Task 11) ✓; narrow-width one-template-per-page paging with swipe-equivalent arrows (Task 11 — note: keyboard/tap arrows only, no finger-drag/edge-dwell paging between templates, since the spec's own "Narrow width" decision only committed to "same swipe/arrow/edge-dwell paging" at the design level; Task 11 ships arrows now and finger-drag paging can be added as a follow-up if the smoke check in Task 13 shows it's needed — flag this to the user at the Task 11 review checkpoint rather than silently shipping a gap); date row/copy button hidden for template blocks (Task 7) ✓; regression coverage (Tasks 8, 13) ✓; out-of-scope items (apply-to-day, reordering, persistence) correctly untouched.
- **Placeholder scan:** no TBD/TODO-as-a-plan-item; the one `TODO(alex)` in Task 5 is copied verbatim from the existing codebase's own comment, not a plan placeholder.
- **Type consistency:** `ScheduleColumn`/`DayColumn`/`TemplateColumn` (Task 1) used identically in Tasks 2–11. `ScheduleController.blocksOf/moveBlock` (Task 2) signatures match every call site in Tasks 5, 10. `ScheduleBlockActions`'s three function-typed fields (Task 7) match `dayScheduleBlockActions`/`templateScheduleBlockActions`'s implementations (Tasks 7, 10) and `BlockEditModal`'s usage (Task 7). `DayGrid`'s `column`/`controller`/`actions` fields (Task 6) match every construction site (Tasks 6 test, 8, 11).
- **Known gap flagged above:** Task 11's narrow-width paging uses tap arrows only, not the finger-drag/edge-dwell mechanism `DayScreen` has — call this out explicitly when presenting Task 11's result, since it's a deliberate scope trim from the design doc's phrasing, not an oversight.
