# Block edit modal — design

## Goal

Give the user a way to edit an existing block: title, start/end time, copy it
to the next day, or delete it. The modal opens on tapping a block (currently
unused on both touch and mouse — taps only dismiss an open draft) and
immediately after a new block is created. It's near-fullscreen on narrow
(mobile) widths and a fixed-width centered dialog on wide (desktop) widths.

## Non-goals

- Category selection — this stage only reserves visual space for a future
  carousel of category squares; no category data model or selection logic.
- Editing `kind` (anchor/frame) or `locked` — fixed at creation, not exposed
  here.
- Undo for delete or copy.
- Pushing/resolving collisions — same as the rest of the app, edits that would
  overlap another block are simply rejected, not resolved by shifting anyone.

## Trigger & lifecycle

- Each non-locked block's existing gesture wiring (`GestureDetector`/
  `RawGestureDetector`, added for drag/resize) gains a plain-tap handler that
  opens the modal for that block. Plain tap is currently free on both touch
  and mouse (move uses long-press/pan, resize uses edge-drag), so this adds a
  new recognizer, not the tap-to-dismiss one already used for locked blocks.
- `DayGrid`'s `onCreateBlock` callback, after the repository call succeeds,
  opens the modal for the newly created block (via the same code path as a
  tap), instead of just leaving it sitting on the grid.
- The modal takes a block `id` and `date`, not a `TimeObject` snapshot, and
  reads the live block from `dayBlocksProvider(date)` each rebuild. If the
  watched block disappears from that list (deleted, or moved off `date` by
  some other interaction), the modal closes itself.

## Layout

`BlockEditModal`, presented via:

- Narrow width (below a new `_editModalBreakpoint`, matching the existing
  `_weekBreakpoint` pattern but its own constant since it answers a different
  question): `showModalBottomSheet` configured to take ~95% of screen height,
  scrollable, drag-to-dismiss.
- Wide width: a centered `Dialog` with a fixed max width (~480px) and
  reasonable max height, via `showDialog`.

Content, top to bottom:

1. Header row: title text field (flex-fills the row) and a close (X)
   `IconButton` at the trailing edge.
2. A horizontal `Row`/`ListView` of empty rounded-square placeholders
   (fixed size, non-interactive, no data binding) reserving the category
   carousel's space.
3. Start time row: label "Starts" + the current time, tapping opens the wheel
   picker.
4. End time row: label "Ends" + the current time, tapping opens the wheel
   picker.
5. A bottom action row with two `IconButton`s, right-aligned: copy-to-next-day
   (duplicate/content-copy icon) and delete (trash icon, styled with the
   error color). Both carry a `tooltip` for accessibility since they have no
   text label.

## Editing behavior

- **Title**: a normal `TextField`; commits via the repository's `update` on
  submit (`onSubmitted`) and on the field losing focus.
- **Start/end**: tapping a time row opens a compact wheel picker (hour +
  minute-in-15-increments, i.e. 4 stops per hour) bounded by the day's
  `dayStartHour`/`dayEndHour`. Only values that keep `start < end`, stay
  on-grid, and don't overlap another block on the same date are selectable —
  same silent-reject-and-snap-back behavior the resize drag already has, so
  there's no separate validation/error UI. Each accepted change commits
  immediately via `update`.
- **Copy to next day**: computed on every rebuild from
  `dayBlocksProvider(date.add(1 day))` — if the block's own `[start, end)`
  overlaps any block already on that date, the icon button is `disabled`
  (its `onPressed` is `null`); otherwise tapping it calls a new repository
  method that adds a copy (same title/kind/times) to the next date, shows a
  brief `SnackBar` confirmation, and leaves the modal open on the original
  block.
- **Delete**: two-tap confirm on the button itself, no separate dialog. First
  tap swaps the icon/tooltip to a confirm state (e.g. a filled warning-colored
  icon, tooltip "Tap again to delete") and starts a short timer (~3s); a
  second tap within that window calls `delete` and closes the modal; letting
  the timer lapse reverts the button to its normal state.

## Data layer additions

`DayBlocksRepository` gains:

```dart
Future<TimeObject> update(
  TimeObject block, {
  required DateTime date,
  String? title,
  DateTime? start,
  DateTime? end,
});

Future<void> delete(TimeObject block, {required DateTime date});
```

`InMemoryDayBlocksRepository`:

- `update` replaces the stored block (promoting a seeded block into `_added`
  the same way `move` already does, marking its id in `_movedSeedIds` so
  `_seedFor` stops re-emitting the stale seed version) and returns the new
  `TimeObject`.
- `delete` removes the block from `_added[date]` if present, otherwise marks
  its id in `_movedSeedIds` so `_seedFor` excludes it going forward (the same
  mechanism already used to suppress a moved seed block).

`DayBlocksNotifier` gains matching `updateBlock`/`deleteBlock` methods that
call the repository and refresh `state`, mirroring `addBlock`/the `move`
commit in `DragNotifier`. Copy-to-next-day is implemented as a call to the
existing `addBlock` equivalent (repository `add`) against
`dayBlocksProvider(nextDate).notifier`, with the source block's title/kind/
duration.

The modal itself doesn't own a Riverpod notifier — it drives
`dayBlocksProvider(date).notifier` directly, the same way today's UI calls
`addBlock`.

## Testing

- Widget tests: tap-to-open on an existing block; modal auto-opens after
  `onCreateBlock`; title edit persists via `update`; time picker rejects an
  overlapping/out-of-grid/inverted candidate and keeps the prior value;
  copy button is disabled when the next day is occupied at that time and
  enabled otherwise, and tapping it when enabled adds the block to the next
  day; delete requires two taps within the timeout window and one tap
  followed by a timeout does not delete; narrow vs. wide width selects
  bottom-sheet vs. dialog presentation.
