# Day Grid Reliability Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `lib/features/day/providers.dart` and
`lib/features/day/widgets/day_grid.dart` — the two largest, most
multi-responsibility files in the day feature — into small,
single-purpose files, and remove the two spots of exact, mechanical
duplication inside `day_grid.dart`. No behavior changes.

**Architecture:** `providers.dart` bundles four Riverpod notifier
families that never call into each other; it splits one-for-one into
four files. `day_grid.dart` bundles the `DayGrid` widget with several
widgets/painters it composes; it splits into one file per
widget/painter group, matching what's already visually distinct in the
file. Two duplicated code blocks (the mouse resize-start/end handles,
and the landzone/resize-draft preview boxes) become one parameterized
private widget/helper each.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`), Dart.

**Spec:** `docs/superpowers/specs/2026-09-19-day-grid-reliability-refactor-design.md`

## Global Constraints

- No behavior changes anywhere in this refactor — every step is either a
  verbatim code move or a mechanical deduplication that preserves exact
  widget keys, geometry, and gesture wiring.
- After every task: `flutter analyze` must report no new issues, and the
  full existing test suite relevant to the day feature (listed per task)
  must pass unchanged. A test needing an import-path update is expected;
  a test needing a *behavior* assertion change means something broke —
  stop and fix the refactor, not the test.
- Widget `Key` strings (e.g. `'day-grid-resize-start-handle'`,
  `'day-grid-landzone'`) must not change — e2e and widget tests locate
  elements by these keys.
- Commit after each task.

---

## Task 1: Split `providers.dart` into one file per notifier family

**Files:**
- Create: `lib/features/day/day_date_provider.dart`
- Create: `lib/features/day/day_blocks_provider.dart`
- Create: `lib/features/day/drag_state_provider.dart`
- Create: `lib/features/day/resize_state_provider.dart`
- Create: `lib/features/day/draft_state_provider.dart`
- Delete: `lib/features/day/providers.dart`
- Modify (update import from `day/providers.dart` to the relevant new
  file(s) above): `lib/core/storage/sembast_overrides.dart`,
  `lib/features/account/account_providers.dart`,
  `lib/features/day/day_schedule_block_actions.dart`,
  `lib/features/day/day_schedule_controller.dart`,
  `lib/features/day/day_screen.dart`,
  `lib/features/day/widgets/apply_template_modal.dart`,
  `lib/features/day/widgets/block_edit_modal.dart`,
  `lib/features/day/widgets/day_grid.dart`,
  `test/unit/day_blocks_apply_template_test.dart`,
  `test/unit/day_blocks_provider_test.dart`,
  `test/unit/day_grid_selectors_test.dart`,
  `test/unit/day_schedule_controller_test.dart`,
  `test/unit/drag_state_provider_test.dart`,
  `test/unit/resize_state_provider_test.dart`,
  `test/unit/sembast_overrides_test.dart`,
  `test/widget/apply_template_modal_test.dart`,
  `test/widget/block_edit_modal_test.dart`,
  `test/widget/day_grid_test.dart`,
  `test/widget/day_screen_test.dart`

**Interfaces:**
- Produces: `selectedDateProvider`, `SelectedDateNotifier` (from
  `day_date_provider.dart`); `dayBlocksRepositoryProvider`,
  `DayBlocksNotifier`, `dayBlocksProvider` (from
  `day_blocks_provider.dart`); `DragTargetResolver`, `DragNotifier`,
  `dragStateProvider`, `dragStateForColumn` (from
  `drag_state_provider.dart`); `ResizeNotifier`, `resizeStateProvider`,
  `resizeStateForColumn` (from `resize_state_provider.dart`);
  `DraftNotifier`, `draftStateProvider`, `draftStateForColumn` (from
  `draft_state_provider.dart`) — all with identical signatures to today,
  just relocated.

- [ ] **Step 1: Baseline — confirm the current suite is green**

Run: `flutter analyze && flutter test test/unit test/widget`
Expected: no analyzer issues, all tests pass. (This is the baseline you
compare against after every later step in this task — if something
fails here, stop and report before touching any code.)

- [ ] **Step 2: Create `day_date_provider.dart`**

Move lines 20–40 of `lib/features/day/providers.dart` (the `_today()`
helper, `SelectedDateNotifier`, and `selectedDateProvider`) verbatim
into a new file:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Holds the date currently shown on the day screen, normalized to
/// midnight.
class SelectedDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => _today();

  /// The selected date. Settable directly so the day view can follow its
  /// own swipe/page navigation.
  DateTime get date => state;
  set date(DateTime value) => state = value;
}

/// The date currently shown on the day screen.
final selectedDateProvider = NotifierProvider<SelectedDateNotifier, DateTime>(
  SelectedDateNotifier.new,
);
```

- [ ] **Step 3: Create `day_blocks_provider.dart`**

Move lines 42–197 of `lib/features/day/providers.dart`
(`dayBlocksRepositoryProvider`, `DayBlocksNotifier`,
`dayBlocksProvider`) verbatim, with these imports:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/template_apply.dart';
import 'package:taskframe/features/template/providers.dart';
```

Body is the exact content of lines 42–197 from the original file (the
`dayBlocksRepositoryProvider` declaration, the full `DayBlocksNotifier`
class, and the `dayBlocksProvider` declaration), unchanged.

- [ ] **Step 4: Create `drag_state_provider.dart`**

Move lines 199–443 of `lib/features/day/providers.dart`
(`DragTargetResolver` typedef, `DragNotifier`, `dragStateProvider`,
`dragStateForColumn`) verbatim, with these imports:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
```

Body is the exact content of lines 199–443 from the original file,
unchanged.

- [ ] **Step 5: Create `resize_state_provider.dart`**

Move lines 445–551 of `lib/features/day/providers.dart`
(`ResizeNotifier`, `resizeStateProvider`, `resizeStateForColumn`, and
the `_minBlockDuration` constant it uses — currently declared at line
18) verbatim, with these imports:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/schedule_controller.dart';

/// The shortest duration a block can be resized down to.
const _minBlockDuration = Duration(minutes: 15);
```

Then the exact content of lines 445–551 from the original file,
unchanged.

- [ ] **Step 6: Create `draft_state_provider.dart`**

Move lines 553–596 of `lib/features/day/providers.dart` (`DraftNotifier`,
`draftStateProvider`, `draftStateForColumn`) verbatim, with these
imports:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/draft_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
```

Body is the exact content of lines 553–596 from the original file,
unchanged.

- [ ] **Step 7: Delete the old file**

Run: `rm lib/features/day/providers.dart`

- [ ] **Step 8: Update every importing file**

In each file listed under **Files → Modify** above, replace its
`import 'package:taskframe/features/day/providers.dart';` line with
imports for whichever of the five new files it actually uses (see
`grep -n` output below per file — import only what's referenced):

```
lib/core/storage/sembast_overrides.dart        -> day_blocks_provider.dart
lib/features/account/account_providers.dart    -> day_blocks_provider.dart
lib/features/day/day_schedule_block_actions.dart -> day_blocks_provider.dart
lib/features/day/day_schedule_controller.dart  -> day_blocks_provider.dart
lib/features/day/day_screen.dart               -> day_blocks_provider.dart, drag_state_provider.dart, day_date_provider.dart
lib/features/day/widgets/apply_template_modal.dart -> day_blocks_provider.dart
lib/features/day/widgets/block_edit_modal.dart -> day_blocks_provider.dart
lib/features/day/widgets/day_grid.dart         -> drag_state_provider.dart, resize_state_provider.dart, draft_state_provider.dart
test/unit/day_blocks_apply_template_test.dart  -> day_blocks_provider.dart
test/unit/day_blocks_provider_test.dart        -> day_blocks_provider.dart
test/unit/day_grid_selectors_test.dart         -> drag_state_provider.dart, resize_state_provider.dart, draft_state_provider.dart
test/unit/day_schedule_controller_test.dart    -> day_blocks_provider.dart
test/unit/drag_state_provider_test.dart        -> day_blocks_provider.dart, drag_state_provider.dart
test/unit/resize_state_provider_test.dart      -> day_blocks_provider.dart, resize_state_provider.dart
test/unit/sembast_overrides_test.dart          -> day_blocks_provider.dart
test/widget/apply_template_modal_test.dart     -> day_blocks_provider.dart
test/widget/block_edit_modal_test.dart         -> day_blocks_provider.dart
test/widget/day_grid_test.dart                 -> day_blocks_provider.dart, drag_state_provider.dart, resize_state_provider.dart, draft_state_provider.dart
test/widget/day_screen_test.dart               -> day_blocks_provider.dart, drag_state_provider.dart, day_date_provider.dart
```

Each new import line follows the existing package-import style, e.g.:
`import 'package:taskframe/features/day/day_blocks_provider.dart';`

- [ ] **Step 9: Fix any remaining import gaps via the analyzer**

Run: `flutter analyze`

If it reports `undefined_identifier` for any of the moved symbols in a
file not listed in Step 8 (a file this plan's `grep` pass missed), add
the corresponding import there too. If it reports `unused_import` for
`day/providers.dart` anywhere, remove that stray import. Repeat until
`flutter analyze` is clean.

- [ ] **Step 10: Run the full test suite**

Run: `flutter test test/unit test/widget`
Expected: identical pass/fail results to Step 1's baseline (all
passing). If a test fails on an assertion (not an import error), stop —
that means a symbol's behavior changed during the move, which should not
happen for a verbatim copy.

- [ ] **Step 11: Run the day-feature e2e specs**

Run: `cd e2e && npx playwright test day-add-event day-apply-template day-block-category day-drag-event day-edit-block day-screen templates-drag-event`
Expected: all pass.

- [ ] **Step 12: Commit**

```bash
git add lib/features/day/day_date_provider.dart lib/features/day/day_blocks_provider.dart lib/features/day/drag_state_provider.dart lib/features/day/resize_state_provider.dart lib/features/day/draft_state_provider.dart
git rm lib/features/day/providers.dart
git add -u
git commit -m "refactor: split day/providers.dart into one file per notifier"
```

---

## Task 2: Split `day_grid.dart` into one file per widget/painter group

**Files:**
- Modify (trim down to just `DayGrid`/`_DayGridState`):
  `lib/features/day/widgets/day_grid.dart`
- Create: `lib/features/day/widgets/draggable_block.dart`
- Create: `lib/features/day/widgets/draft_overlay.dart`
- Create: `lib/features/day/widgets/day_grid_painters.dart`
- Create: `lib/features/day/widgets/template_apply_visuals.dart`
- Modify (add an import for `resizeEdgeForLocalY`/`resizeBleedForBlocks`,
  now in `draggable_block.dart`): `test/widget/day_grid_test.dart`

**Interfaces:**
- Consumes: `dragStateProvider`, `resizeStateProvider`,
  `draftStateProvider` from Task 1's new files;
  `dragStateForColumn`/`resizeStateForColumn`/`draftStateForColumn`
  selectors from Task 1's new files.
- Produces: `DraggableBlock` (renamed from `_DraggableBlock`, now
  public), `resizeEdgeForLocalY`, `resizeBleedForBlocks` (from
  `draggable_block.dart`); no other new public symbols — `DayGrid`
  itself keeps its existing public API unchanged.

- [ ] **Step 1: Baseline**

Run: `flutter analyze && flutter test test/unit test/widget`
Expected: clean, matching Task 1's final state.

- [ ] **Step 2: Create `template_apply_visuals.dart`**

Move lines 710–827 of `lib/features/day/widgets/day_grid.dart`
(`_TemplateHighlightPulse`, `_TemplateHighlightPulseState`,
`_TemplateGhostOverlay`, `_TemplateGhostOverlayState`) verbatim, with
these imports:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:taskframe/features/day/template_apply_effects.dart';
```

- [ ] **Step 3: Create `day_grid_painters.dart`**

Move lines 1416–1548 of `lib/features/day/widgets/day_grid.dart`
(`_DashedBorderPainter`, `_DayGridPainter`, `_NowLinePainter`) verbatim,
with this import:

```dart
import 'package:flutter/material.dart';
```

- [ ] **Step 4: Create `draft_overlay.dart`**

Move lines 1325–1414 of `lib/features/day/widgets/day_grid.dart`
(`_DraftOverlay`, `_DraftButton`) verbatim, with these imports:

```dart
import 'package:flutter/material.dart';
import 'package:taskframe/features/day/widgets/block_kind_style.dart';
import 'package:taskframe/features/day/widgets/day_grid_painters.dart';
import 'package:taskframe/features/day/models/time_object.dart';
```

(`day_grid_painters.dart` is needed here for `_DashedBorderPainter`,
which `_DraftOverlay` paints with; `models/time_object.dart` for
`BlockKind`.)

- [ ] **Step 5: Create `draggable_block.dart`**

Move lines 829–1323 of `lib/features/day/widgets/day_grid.dart` (the
doc comment plus `resizeEdgeForLocalY`, `resizeBleedForBlocks`,
`_DraggableBlock`, `_DraggableBlockState`) verbatim except renaming
`_DraggableBlock` to `DraggableBlock` everywhere it's referenced
(the class declaration, its constructor, and
`ConsumerState<_DraggableBlock>`/`ConsumerState<DraggableBlock>` in
`_DraggableBlockState`'s `createState`), with these imports:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/drag_state_provider.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/resize_state_provider.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
```

(`day_new_block.dart` is needed for `resizeCandidateForOffset`, called
by `_DraggableBlockState._updateResize`.)

- [ ] **Step 6: Trim `day_grid.dart` down to `DayGrid`/`_DayGridState`**

Delete lines 710–1548 from `lib/features/day/widgets/day_grid.dart`
(everything moved in Steps 2–5), leaving only the file header comment,
imports, and lines 24–708 (`DayGrid` + `_DayGridState`). Update the
remaining import block (originally lines 1–22) to:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/draft_state_provider.dart';
import 'package:taskframe/features/day/drag_state_provider.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/resize_state_provider.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
import 'package:taskframe/features/day/template_apply_effects.dart';
import 'package:taskframe/features/day/week_utils.dart';
import 'package:taskframe/features/day/widgets/block_view.dart';
import 'package:taskframe/features/day/widgets/draft_overlay.dart';
import 'package:taskframe/features/day/widgets/draggable_block.dart';
import 'package:taskframe/features/day/widgets/day_grid_painters.dart';
import 'package:taskframe/features/day/widgets/schedule_block_actions.dart';
import 'package:taskframe/features/day/widgets/template_apply_visuals.dart';
```

Then, in the remaining `_DayGridState.build()` method, rename every
`_DraggableBlock(` constructor call to `DraggableBlock(` (there is
exactly one, in the per-block `Positioned` loop).

- [ ] **Step 7: Fix imports via the analyzer**

Run: `flutter analyze`

Fix any `undefined_identifier`/`unused_import`/`undefined_class`
reported in the four new files or in `day_grid.dart` by adding or
removing the specific import named in the error — repeat until clean.
Common ones to expect: `block_kind_style.dart`'s `BlockKindStyle`
extension needs no explicit import at its use site inside
`draft_overlay.dart` beyond what's listed above; double check
`day_grid.dart` no longer needs `block_kind_style.dart` (it shouldn't,
since `BlockKind` styling is only used inside the moved `_DraftOverlay`).

- [ ] **Step 8: Update `day_grid_test.dart`'s import**

`test/widget/day_grid_test.dart` calls `resizeEdgeForLocalY` and
`resizeBleedForBlocks` directly (see its `group('resizeEdgeForLocalY', ...)`
and `group('resizeBleedForBlocks', ...)` blocks). Add:

```dart
import 'package:taskframe/features/day/widgets/draggable_block.dart';
```

to its import list (it already imports `day_grid.dart`, which no
longer re-exports these two functions).

- [ ] **Step 9: Run the full test suite**

Run: `flutter analyze && flutter test test/unit test/widget`
Expected: no analyzer issues; all tests pass, identical results to
Step 1's baseline.

- [ ] **Step 10: Run the day-feature e2e specs**

Run: `cd e2e && npx playwright test day-add-event day-apply-template day-block-category day-drag-event day-edit-block day-screen templates-drag-event`
Expected: all pass.

- [ ] **Step 11: Commit**

```bash
git add lib/features/day/widgets/day_grid.dart lib/features/day/widgets/draggable_block.dart lib/features/day/widgets/draft_overlay.dart lib/features/day/widgets/day_grid_painters.dart lib/features/day/widgets/template_apply_visuals.dart test/widget/day_grid_test.dart
git commit -m "refactor: split day_grid.dart into one file per widget/painter group"
```

---

## Task 3: Deduplicate the mouse resize-start/end handles

**Files:**
- Modify: `lib/features/day/widgets/draggable_block.dart`
- Test: `test/widget/day_grid_test.dart` (existing resize/drag tests —
  no new test file; this task's correctness is proven by the existing
  suite plus a new characterization check in Step 2)

**Interfaces:**
- Consumes: `ResizeEdge` from `lib/features/day/models/resize_state.dart`
  (already imported by `draggable_block.dart`).
- Produces: private `_ResizeHandle` widget, used only within
  `draggable_block.dart`.

- [ ] **Step 1: Baseline**

Run: `flutter analyze && flutter test test/unit test/widget`
Expected: clean, matching Task 2's final state.

- [ ] **Step 2: Confirm current resize-handle behavior is covered**

Run: `flutter test test/widget/day_grid_test.dart -N resize`
Expected: existing resize-drag tests pass (they exercise both the
start-edge and end-edge handles via their keys
`day-grid-resize-start-handle` / `day-grid-resize-end-handle` — this
task must not change those keys or the geometry they're positioned
with).

- [ ] **Step 3: Add the `_ResizeHandle` widget**

In `lib/features/day/widgets/draggable_block.dart`, add this class
(placed after `_DraggableBlockState`, before end of file):

```dart
/// One mouse resize strip — the thin, precise handle sitting at a
/// block's true top or bottom edge (see [_DraggableBlockState.build]'s
/// "classic" desktop resize handles comment). Identical for the start
/// and end edges except for [edge], geometry, and which
/// [_DraggableBlockState] callback each drag stage invokes.
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.resizeKey,
    required this.top,
    required this.height,
    required this.edge,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final Key resizeKey;
  final double top;
  final double height;
  final ResizeEdge edge;

  /// Called on drag start with [edge] and the pointer's global position —
  /// the caller both starts the resize for [edge] and immediately applies
  /// this first position, matching the original two call sites' comment
  /// about the arena resolving mid-gesture.
  final void Function(ResizeEdge edge, Offset globalPosition) onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: resizeKey,
      top: top,
      left: 0,
      right: 0,
      height: height,
      child: MouseRegion(
        // See the original handles' comment: `opaque: false` so a pointer
        // outside this strip's own recognizer still reaches the touch
        // race zone and move detector beneath it.
        opaque: false,
        cursor: SystemMouseCursors.resizeRow,
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: {
            VerticalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  VerticalDragGestureRecognizer
                >(
                  () => VerticalDragGestureRecognizer()
                    ..supportedDevices = {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                    },
                  (recognizer) {
                    recognizer
                      ..onStart = (details) =>
                          onStart(edge, details.globalPosition)
                      ..onUpdate = (details) => onUpdate(details.globalPosition)
                      ..onEnd = (_) => onEnd()
                      ..onCancel = onCancel;
                  },
                ),
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Replace both handle blocks with `_ResizeHandle`**

In `_DraggableBlockState.build()`, replace the two `Positioned(key:
const Key('day-grid-resize-start-handle'), ...)` and `Positioned(key:
const Key('day-grid-resize-end-handle'), ...)` blocks (everything from
each `Positioned(` through its matching closing `),`) with:

```dart
_ResizeHandle(
  resizeKey: const Key('day-grid-resize-start-handle'),
  top: topBleed - topOvershoot,
  height: topOvershoot + topStripBottom,
  edge: ResizeEdge.start,
  onStart: (edge, position) {
    _startResize(edge);
    _updateResize(position);
  },
  onUpdate: _updateResize,
  onEnd: _endResize,
  onCancel: _cancelResize,
),
_ResizeHandle(
  resizeKey: const Key('day-grid-resize-end-handle'),
  top: topBleed + bottomStripTop,
  height: (blockHeight + bottomOvershoot) - bottomStripTop,
  edge: ResizeEdge.end,
  onStart: (edge, position) {
    _startResize(edge);
    _updateResize(position);
  },
  onUpdate: _updateResize,
  onEnd: _endResize,
  onCancel: _cancelResize,
),
```

- [ ] **Step 5: Run the full test suite**

Run: `flutter analyze && flutter test test/unit test/widget`
Expected: no analyzer issues; identical pass results to Step 1's
baseline, including every resize-related test.

- [ ] **Step 6: Run the drag/resize e2e specs**

Run: `cd e2e && npx playwright test day-drag-event day-edit-block templates-drag-event`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/day/widgets/draggable_block.dart
git commit -m "refactor: deduplicate mouse resize-handle widgets"
```

---

## Task 4: Deduplicate the landzone/resize-draft preview boxes

**Files:**
- Modify: `lib/features/day/widgets/day_grid.dart`
- Test: existing `test/widget/day_grid_test.dart`,
  `test/widget/day_grid_apply_effects_test.dart` (no new test file —
  see note below on scope)

**Interfaces:**
- Consumes: `_offsetFor`, `_categoryFor`, `_gridLeft` (existing
  `_DayGridState` members).
- Produces: private `_DayGridState._previewBox` method, used only
  within `day_grid.dart`.

**Note — refinement from the spec:** the spec described unifying all
*three* block-visual call sites (real block, landzone, resize-draft)
into one helper. Reading the actual code shows the real block's visual
is materially different — it's built as `DraggableBlock`'s `child`
parameter, participates in the `hiddenBlockId`/highlight-pulse
conditional, and its box position already accounts for resize bleed.
Only the landzone and resize-draft cases are byte-for-byte identical
(both: a dashed, `IgnorePointer`-wrapped, surface-colored `BlockView`
box positioned by `_offsetFor`, followed by a separate `_titleOverlay`
call). This task unifies those two only; the real block's rendering in
the per-block `Positioned` loop is left as-is.

- [ ] **Step 1: Baseline**

Run: `flutter analyze && flutter test test/unit test/widget`
Expected: clean, matching Task 3's final state.

- [ ] **Step 2: Add the `_previewBox` helper**

In `lib/features/day/widgets/day_grid.dart`, add this method to
`_DayGridState` (placed after `_titleOverlay`):

```dart
  /// The landzone/resize-draft preview box for [block] spanning
  /// `[start, end)`: a dashed, non-interactive outline around a
  /// surface-colored [BlockView], used by both the drag landzone and the
  /// resize draft — the two places `DayGrid` shows a block "as it would
  /// be" rather than as it currently is. Returns the box alongside its
  /// own top/height so the caller's matching [_titleOverlay] call reuses
  /// them instead of recomputing [_offsetFor] a second time.
  ({Widget box, double top, double height}) _previewBox({
    required Key boxKey,
    required TimeObject block,
    required DateTime start,
    required DateTime end,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final top = _offsetFor(start);
    final height = _offsetFor(end) - top;
    final box = Positioned(
      key: boxKey,
      top: top,
      left: _gridLeft,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DashedBorderPainter(color: scheme.primary),
          child: Container(
            color: scheme.surface,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: BlockView(
              block: block,
              showTitle: false,
              category: _categoryFor(block),
            ),
          ),
        ),
      ),
    );
    return (box: box, top: top, height: height);
  }
```

- [ ] **Step 3: Precompute both previews before the `Stack`'s children**

`dragState` and `resizeState` are already computed as locals earlier in
`build()` (via `ref.watch(...)`), right before `resizeBleed`. Add two
more locals right after `resizeBleed` is computed, reusing
`_previewBox`:

```dart
    final landzonePreview = dragState != null && landzoneStart != null
        ? _previewBox(
            boxKey: const Key('day-grid-landzone'),
            block: dragState.block,
            start: landzoneStart,
            end: landzoneStart.add(
              dragState.block.end.difference(dragState.block.start),
            ),
          )
        : null;
    final resizeDraftPreview =
        resizeState != null && resizeState.column == widget.column
        ? _previewBox(
            boxKey: const Key('day-grid-resize-draft'),
            block: resizeState.block,
            start: resizeState.draftStart,
            end: resizeState.draftEnd,
          )
        : null;
```

- [ ] **Step 4: Use the precomputed previews for the landzone and resize draft**

Replace the landzone's `Positioned(key: const Key('day-grid-landzone'),
...)` block and its `_titleOverlay` call with:

```dart
            if (landzonePreview != null) ...[
              landzonePreview.box,
              _titleOverlay(
                key: const Key('day-grid-landzone-title'),
                block: dragState!.block,
                trueTop: landzonePreview.top,
                trueHeight: landzonePreview.height,
              ),
            ],
```

And replace the resize-draft's `Positioned(key: const
Key('day-grid-resize-draft'), ...)` block and its `_titleOverlay` call
with:

```dart
            if (resizeDraftPreview != null) ...[
              resizeDraftPreview.box,
              _titleOverlay(
                key: const Key('day-grid-resize-draft-title'),
                block: resizeState!.block,
                trueTop: resizeDraftPreview.top,
                trueHeight: resizeDraftPreview.height,
              ),
            ],
```

(`dragState!`/`resizeState!` are safe here: `landzonePreview`/
`resizeDraftPreview` being non-null was derived from `dragState`/
`resizeState` being non-null in the ternaries above, but Dart's flow
analysis doesn't propagate that promotion across the two separate
locals, so the explicit `!` is required — both are the same locals
already null-checked to compute the preview two lines above, so this
can't actually fail at runtime.)

- [ ] **Step 5: Remove the now-unused `_landzoneHeightFor` helper if it is dead code**

Run: `grep -n "_landzoneHeightFor" lib/features/day/widgets/day_grid.dart`

If the only remaining match is the method's own declaration (its call
site was replaced in Step 3 by `_previewBox`'s `end` computation),
delete the `_landzoneHeightFor` method entirely. If it's still
referenced elsewhere, leave it.

- [ ] **Step 6: Run the full test suite**

Run: `flutter analyze && flutter test test/unit test/widget`
Expected: no analyzer issues (in particular, no `unused_element` for
`_landzoneHeightFor` if Step 5 removed it correctly); identical pass
results to Step 1's baseline, including
`day_grid_apply_effects_test.dart`, which exercises the landzone/ghost
visuals directly.

- [ ] **Step 7: Run the drag/resize/apply e2e specs**

Run: `cd e2e && npx playwright test day-drag-event day-edit-block day-apply-template templates-drag-event`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add lib/features/day/widgets/day_grid.dart
git commit -m "refactor: deduplicate landzone/resize-draft preview boxes"
```
