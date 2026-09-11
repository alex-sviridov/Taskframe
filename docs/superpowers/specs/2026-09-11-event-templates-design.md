# Event templates (stage 1: template editor)

## Purpose

Templates are reusable sets of events, the same shape as a day's schedule,
that can later be applied to a real day. This is stage 1 only: a new
`/templates` path where templates can be created, named, removed, and
edited with the same schedule UI the Day screen already has (add/edit/
delete/drag/resize blocks). Applying a template to a day is a future
stage and is not implemented here.

## Scope

In scope:
- A `Template` model and repository (in-memory), independent of calendar
  dates
- A `ScheduleColumn` abstraction that splits "which column a block lives
  in" (a date, or a template id) from "what time of day a block
  occupies" (still `DateTime`, used only for its hour/minute), so the
  existing grid/drag/resize/edit-modal code can be shared between Day and
  Templates instead of duplicated
- `TemplatesScreen`: a new top-level nav destination reusing `DayScreen`'s
  paging/column layout, with templates as columns instead of dates, and
  add/remove-template controls
- `BlockEditModal` adjusted to hide the date row and "copy to next day"
  action when editing a template's block
- Tests for the new model/providers and for `TemplatesScreen`, plus
  regression coverage confirming `DayScreen` behavior is unchanged

Out of scope:
- Applying a template to a day (copying its blocks onto a real date) —
  the design doesn't preclude it (see Future work) but no UI or code for
  it exists yet
- Reordering templates (list order = creation order for stage 1)
- Any backing store beyond in-memory (matches the current day feature)

## Decisions

- **`DateTime` stays the block time-of-day type; column identity moves to
  a new `ScheduleColumn`.** Every grid/drag/resize calculation in
  `day_new_block.dart` and `DayGrid` only ever reads a `DateTime`'s
  `hour`/`minute` — the date component is already incidental to the math.
  Rather than inventing a new time-of-day value type (which would ripple
  through every function signature in `day_new_block.dart`), a template
  block's `start`/`end` use one fixed, internal sentinel date shared by
  every template block everywhere. That date is never read as meaning
  anything and never used for identity — `ScheduleColumn` is the identity
  now, not the `DateTime`. This was chosen over duplicating a parallel
  `TemplateGrid`/`TemplateDragNotifier`/etc. module, because the
  duplication would immediately fork ~1000 lines of gesture-handling code
  (see `DragNotifier`'s pointer-ownership docs in `providers.dart`) that
  would need reconciling by hand whenever either side changes.
- **`ScheduleColumn` is a sealed type**, `DayColumn(DateTime date)` |
  `TemplateColumn(String templateId)`, with value equality. It replaces
  `DateTime` wherever it was previously used purely as a column's
  identity: `dayGridKeyFor` (→ `scheduleGridKeyFor`), `DragState`'s
  `originalDate`/`targetDate` (→ `originalColumn`/`targetColumn`),
  `ResizeState.date` (→ `column`), and `resolveDragTarget`'s
  `candidateDates`/return value.
- **`DragNotifier`/`ResizeNotifier` read and write blocks through a new
  `ScheduleController` interface** (`blocksFor`, `move`), rather than
  reading `dayBlocksProvider`/`dayBlocksRepositoryProvider` directly. Two
  implementations: `DayScheduleController` (today's behavior) and
  `TemplateScheduleController` (wraps the new template repository). Each
  notifier resolves the right controller from the `ScheduleColumn`
  variant of the block it's currently dragging/resizing, so a single drag
  gesture never needs to know in advance whether it's touching a day or a
  template column — this also makes cross-column drags within
  `TemplatesScreen` work the same way cross-day drags already do in week
  view.
- **`BlockEditModal` takes a `column: ScheduleColumn`** instead of a bare
  `date: DateTime`. When `column` is a `TemplateColumn`, the date row and
  "copy to next day" button are omitted; everything else (title, category
  picker, start/end editing, kind, delete) is identical to today.
- **File layout unchanged for shared code.** `ScheduleColumn`,
  `ScheduleController`, and the genericized `DayGrid`/`DragNotifier`/
  `ResizeNotifier`/`block_edit_modal.dart` stay in `lib/features/day/` —
  it's already the natural home for schedule-grid concepts and a rename
  isn't needed for this stage. Template-specific code (`Template`,
  `TemplateRepository`, providers, `TemplatesScreen`,
  `TemplateScheduleController`) lives in a new `lib/features/template/`.
- **No new adaptive-layout mechanics.** `TemplatesScreen` reuses
  `DayScreen`'s existing narrow/wide split: narrow pages one template at
  a time (same swipe/edge-dwell paging as Day), wide shows every template
  as a side-by-side column (no 7-column cap or week-breakpoint math —
  just however many templates exist, scrollable if they overflow).

## Data model

```dart
// lib/features/day/models/schedule_column.dart
sealed class ScheduleColumn {
  const ScheduleColumn();
}

class DayColumn extends ScheduleColumn {
  const DayColumn(this.date);
  final DateTime date; // == and hashCode by calendar day
}

class TemplateColumn extends ScheduleColumn {
  const TemplateColumn(this.templateId);
  final String templateId; // == and hashCode by templateId
}
```

```dart
// lib/features/template/models/template.dart
class Template {
  const Template({required this.id, required this.name});
  final String id;
  final String name;
}
```

`TemplateBlocksRepository` mirrors `DayBlocksRepository`'s shape (`load`,
`add`, `move`, `update`, `delete`) but keyed by `templateId: String`
instead of `date: DateTime`, with no seed data and no `copyToNextDay`
equivalent. `templateBlocksProvider` is an
`AsyncNotifierProvider.family<TemplateBlocksNotifier, List<TimeObject>,
String>`, structurally parallel to `dayBlocksProvider`. `templateListProvider`
holds the ordered `List<Template>` and exposes add/remove/rename.

## Routing and navigation

`/templates` becomes a third `StatefulShellRoute` branch in
`lib/router.dart`, alongside `/` (Day) and `/categories`, with its own
`AppShell` nav entry ("Templates").

## `TemplatesScreen`

Structurally a copy of `DayScreen`'s page/column shell (`PageView` +
`_SchedulePage`-equivalent), paging over the ordered template list
instead of over dates:
- Narrow width: one template per page, same swipe/arrow/edge-dwell
  paging `DayScreen` uses between days.
- Wide width: every template shown as a column, side by side (reusing
  `HourGutter`/`DayGrid`'s week-view column layout, without the 7-day
  cap).
- Each column's header shows the template's name (inline-editable, like
  a title field) instead of a date, plus a delete action.
- A `+` button (app bar, matching Day's "Add block" placement) appends a
  new template (default name, e.g. "Template N") and opens it.

`DayGrid` itself needs no rename or behavioral change beyond accepting a
`ScheduleColumn column` field alongside its existing `date: DateTime`
(the latter still drives grid math and the "now" line, which never
applies to a `TemplateColumn`).

## Testing

- Unit tests: `ScheduleColumn` equality/hashing; `TemplateRepository`/
  `templateListProvider`/`templateBlocksProvider` (add/remove/rename,
  load/add/move/update/delete blocks).
- Widget tests: `templates_screen_test.dart` mirroring
  `day_screen_test.dart`'s coverage — add/remove a template, narrow-width
  paging, drag a block within a template column and across two template
  columns, resize, edit via `BlockEditModal` (confirming the date row and
  copy button are absent).
- Regression: existing `day_screen_test.dart` and `router_test.dart` must
  keep passing unchanged after `DragNotifier`/`ResizeNotifier`/
  `BlockEditModal`/`dayGridKeyFor` are genericized, confirming Day
  behavior is bit-for-bit the same.

## Future work (not this stage)

Applying a template to a day: for each of the template's blocks, add a
day block at the target date with that block's own hour/minute, via the
existing `DayBlocksRepository.add`. Nothing in this design blocks that —
a template block's hour/minute already means exactly what a day block's
hour/minute means — but no UI or apply-flow code is built yet.
