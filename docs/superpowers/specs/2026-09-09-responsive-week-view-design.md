# Responsive week view design

## Problem

The day screen currently shows exactly one day, infinitely stretched
horizontally to fill the viewport. On wide screens (desktop, tablet
landscape) that wastes space — there's room to show the whole week at
once. We want the schedule screen to switch between a single-day layout
(narrow) and a full 7-day week layout (wide), sharing as much of the
existing day-view implementation as possible, and to lay groundwork for
two settings (first day of week, date format) without yet building a
settings UI.

## Goals

- Below a width breakpoint: today's single-day view, unchanged in
  behavior.
- At/above the breakpoint: a full week (7 days) is shown at once, with
  the same finger-tracked swipe/page animation, now paging by a whole
  week per swipe.
- Every day (in either mode) shows its date at the top of its column.
- In week mode, the day-of-week name is dropped from each column's
  date label (day mode keeps it).
- `firstDayOfWeek` and `dateFormat` become configurable via hardcoded
  provider values (same pattern as today's `dayStartHour`/
  `dayEndHour`) — no settings screen or persistence yet, but the
  seams are in place for one later.
- Maximize reuse between day and week rendering; avoid duplicating the
  paging/gesture/animation logic.

## Non-goals

- No settings screen, no `shared_preferences` persistence. Settings
  stay hardcoded constants in the provider.
- No change to block creation, block data model, or the day grid's
  visual style beyond what's needed for the shared hour gutter.

## Breakpoint

`daysPerPage = width >= 900 ? 7 : 1`, measured via `LayoutBuilder` in
`DayScreen`'s build method. 900px roughly matches tablet-landscape and
up.

## Settings

Extend `DaySettings` (`day_settings.dart`) with two more hardcoded
fields, following the file's existing pattern and comment style:

- `firstDayOfWeek` — an `int` weekday (`DateTime.monday`..
  `DateTime.sunday`), default `DateTime.monday`.
- `dateFormat` — a pattern `String` using `dd`/`MM`/`yyyy` tokens,
  default `'dd/MM/yyyy'` (European). A US-style alternative would be
  `'MM/dd/yyyy'`.

## Date formatting

Replace `date_format.dart`'s hardcoded `formatDayLabel` with two
functions:

- `String formatDate(DateTime date, String pattern)` — substitutes
  `dd`, `MM`, `yyyy` tokens in `pattern` with the date's
  zero-padded day, zero-padded month, and 4-digit year.
- `String formatDayHeaderLabel(DateTime date, {required bool
  showWeekday, required String pattern})` — returns
  `"Wednesday, 09/09/2026"` when `showWeekday` is `true` (day view),
  or `"09/09/2026"` when `false` (week view column headers). The
  weekday name table currently in `date_format.dart` moves here
  unchanged.

## Component restructuring

Keep a single `DayScreen` widget rather than splitting into separate
`DayScreen`/`WeekScreen` widgets — a split would duplicate the
`PageController`, swipe-forwarding, and edge-fade logic that's
independent of how many days are on screen. Instead, `DayScreen`
becomes generic over `daysPerPage`:

- **Paging math.** In day mode (`daysPerPage == 1`), page N maps to
  `anchor + N days`, as today. In week mode (`daysPerPage == 7`),
  page N maps to the `firstDayOfWeek`-aligned week start `+ N*7
  days`, via a new `startOfWeek(DateTime date, {required int
  firstDayOfWeek})` helper. Switch arrows animate by `daysPerPage`.
- **Mode switches preserve the selected date, not the raw page
  index.** If the viewport crosses the 900px breakpoint (e.g. a
  resized browser window), the `PageController` is rebuilt with a new
  `initialPage` computed so the date that was visible stays visible,
  rather than reinterpreting the old page index under the new
  paging unit.
- **Page content.** `_DayPage` is replaced by `_SchedulePage(startDate,
  dayCount)`, which lays out `dayCount` `_DayColumn` widgets (each a
  header + the existing `DayGrid`, unchanged) in a `Row`. Each
  column's header uses `formatDayHeaderLabel` with `showWeekday:
  dayCount == 1`.
- **Hour labels.** `DayGrid` gains a `showHourLabels` bool (default
  `true`). Day mode (`dayCount == 1`) keeps `showHourLabels: true`
  and its own 48px label gutter, unchanged from today. Week mode
  (`dayCount == 7`) sets `showHourLabels: false` on every column
  (dropping their left inset) and adds one new `HourGutter` widget
  once, to the left of all 7 columns, drawing just the hour labels
  and lines using the same slot-height math as `DayGrid`'s painter.
- **Scrolling.** The whole page (gutter + columns) is one
  `SingleChildScrollView`, so all columns and the gutter scroll in
  sync.
- **Gestures.** Each column's `DayGrid` independently handles its own
  tap/long-press-to-create-block (as today, scoped to that column's
  `date`) and forwards horizontal drags to the same page-level swipe
  callback, so a swipe starting on any column's grid still drives the
  shared `PageController`.

## Files touched

- `day_settings.dart` — add `firstDayOfWeek`, `dateFormat`.
- `date_format.dart` — replace `formatDayLabel` with `formatDate` +
  `formatDayHeaderLabel`.
- `day_screen.dart` — responsive `daysPerPage`, generalized
  page↔date mapping, `_SchedulePage`/`_DayColumn`, mode-switch
  handling.
- `widgets/day_grid.dart` — add `showHourLabels` param; adjust left
  inset and painter when `false`.
- `widgets/hour_gutter.dart` (new) — shared hour-label column for
  week mode.
- `week_utils.dart` (new) or added to `day_grid_sizing.dart` —
  `startOfWeek` helper.

## Testing

- Unit: `formatDate`/`formatDayHeaderLabel` for both pattern styles
  and both `showWeekday` values; `startOfWeek` for both Monday- and
  Sunday-first settings.
- Widget: extend `day_screen_test.dart` to cover narrow (1-day) vs.
  wide (7-day) layouts, correct week-start alignment per
  `firstDayOfWeek`, weekday name present/absent per mode, and the
  resize-preserves-selected-date behavior. Extend `day_grid_test.dart`
  for `showHourLabels: false`.
- E2E: `day-screen.spec.ts` and `day-add-event.spec.ts` currently run
  at Playwright's default viewport, which is likely ≥900px wide and
  would now hit week view instead of day view. Pin these specs to an
  explicit narrow viewport so they keep testing day view as before,
  and add a new e2e spec exercising week view at a wide viewport.
