# Day grid reliability refactor

## Motivation

A general code-health pass, starting with the day feature: `day_grid.dart`
(1548 lines) and `providers.dart` (596 lines) are the two largest and most
tangled files in the app. Both bundle several independent responsibilities
into one file, which makes it easy to break something unrelated while
touching either of them. Neither file is sloppy — both are heavily and
carefully commented, with subtle gesture-arena and pointer-ownership
behavior explicitly justified — so the goal is to reduce the surface area
each file exposes and remove the small amount of genuine duplication in
`day_grid.dart`, not to rewrite the underlying logic.

## Scope

In scope: `lib/features/day/widgets/day_grid.dart` and
`lib/features/day/providers.dart`.

Out of scope: every other file in `lib/features/day/`, and other oversized
files elsewhere in the app (`task_edit_modal.dart`, `block_edit_modal.dart`,
`tasks_screen.dart`, etc.) — candidates for a future pass if this one goes
well.

No behavior changes are intended anywhere in this refactor. Existing
coverage (listed under Testing) is the safety net that verifies that.

## Design

### 1. Split `providers.dart` into one file per notifier family

The four notifiers in `providers.dart` don't call into each other directly
— they're only related through the `ScheduleController` abstraction and
shared UI state — so splitting them is a pure move, no logic changes:

- `day_date_provider.dart` — `SelectedDateNotifier` / `selectedDateProvider`
- `day_blocks_provider.dart` — `dayBlocksRepositoryProvider`,
  `DayBlocksNotifier` / `dayBlocksProvider`
- `drag_state_provider.dart` — `DragTargetResolver`, `DragNotifier` /
  `dragStateProvider`, `dragStateForColumn`
- `resize_state_provider.dart` — `ResizeNotifier` / `resizeStateProvider`,
  `resizeStateForColumn`
- `draft_state_provider.dart` — `DraftNotifier` / `draftStateProvider`,
  `draftStateForColumn`

Each file keeps its provider's selector function (e.g.
`dragStateForColumn`) alongside it rather than in a separate selectors
file, since each selector is only ever used with its own provider.

`providers.dart` itself is deleted once every symbol has moved; call sites
update their imports to the new file paths.

### 2. Split `day_grid.dart` into 5 files by widget

- `day_grid.dart` — kept as the file name; holds only `DayGrid` /
  `_DayGridState` (gesture detection + layout orchestration)
- `draggable_block.dart` — `_DraggableBlock`, promoted to a public
  `DraggableBlock` (it's the largest remaining chunk, and the natural
  location for the resize-handle extraction below)
- `draft_overlay.dart` — `_DraftOverlay` + `_DraftButton`
- `day_grid_painters.dart` — `_DashedBorderPainter`, `_DayGridPainter`,
  `_NowLinePainter`
- `template_apply_visuals.dart` — `_TemplateHighlightPulse`,
  `_TemplateGhostOverlay`

Free functions currently living in `day_grid.dart` move with the widget
that uses them: `resizeEdgeForLocalY` and `resizeBleedForBlocks` go to
`draggable_block.dart` (both are `_DraggableBlock`/`DayGrid`-internal
geometry helpers used only there).

### 3. Targeted deduplication

Two places have exact, mechanical duplication worth collapsing — both
pure extractions, no behavior change:

- **Mouse resize handles.** `_DraggableBlock` currently has two ~80-line
  blocks (`day-grid-resize-start-handle` / `day-grid-resize-end-handle`)
  that differ only in which `ResizeEdge` they start and which vertical
  strip they occupy. These become one private `_ResizeHandle` widget
  parameterized by `edge`, `top`, and `height`, used twice.
- **Block visual + title overlay.** `DayGrid.build()` currently repeats
  the same "surface-colored box wrapping a `BlockView`, plus a matching
  `_titleOverlay` call" pattern three times (the real block, the drag
  landzone, and the resize draft), each with its own key. These collapse
  into one `_blockVisual({required Key boxKey, required Key titleKey,
  required TimeObject block, required double top, required double
  height, bool dashed = false})` helper, used by all three call sites (the
  dashed border only applies to the landzone/resize-draft cases).

### Explicitly not simplified

`DragNotifier`'s global-pointer-route ownership dance and
`ResizeNotifier`'s edge-clamping logic are left untouched. Both are
already minimal for the guarantee they provide, and each non-obvious line
is justified by an existing comment (e.g. why a global route survives a
mid-drag page unmount, why resize clamping walks neighbor blocks rather
than using a fixed bound). Rewriting them would add risk to genuinely
tricky gesture-handling code for no measurable simplicity gain, so this
refactor's "targeted simplification" stops at structural/mechanical
deduplication.

## Testing

No behavior changes are intended, so verification is regression-only.
After each extraction step:

- `flutter analyze`
- Unit/widget tests: `day_grid_test.dart`, `day_grid_selectors_test.dart`,
  `day_grid_apply_effects_test.dart`, `drag_state_provider_test.dart`,
  `drag_state_test.dart`, `resize_state_provider_test.dart`,
  `resize_state_test.dart`, `drag_target_resolver_test.dart`,
  `day_screen_test.dart`, `router_drag_test.dart`
- e2e specs: `day-add-event.spec.ts`, `day-drag-event.spec.ts`,
  `day-edit-block.spec.ts`, `day-apply-template.spec.ts`,
  `day-block-category.spec.ts`, `day-screen.spec.ts`,
  `templates-drag-event.spec.ts`

If any of these need updating, it should only be for import-path changes
(e.g. `_DraggableBlock` renamed to `DraggableBlock`) — a test asserting on
renamed/moved internals is expected; a test asserting on different
*behavior* would mean the refactor introduced a regression and should be
treated as a bug, not accommodated.
