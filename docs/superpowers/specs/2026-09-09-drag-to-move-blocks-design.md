# Drag-to-move blocks — design

## Goal

Let a user pick up an existing block on the schedule grid and move it: long-press
on touch or click-and-drag on desktop starts the move, a "landzone" shadow shows
where it will land (snapped to the 15-minute grid), the move can cross into
another day or week, and dragging near the screen edge auto-pages to the
adjacent day/week. Releasing the drag commits the move (updates the block's
date/time). Pushing or resolving collisions with other blocks is explicitly out
of scope for this stage — a moved block may land overlapping another block, or
overlapping its own original position, with no special handling.

## Non-goals

- Collision detection / pushing other blocks out of the way.
- Resizing a block (only moving its start/end as a fixed-duration unit).
- Any drag affordance for `locked` blocks.

## Architecture & data flow

A new ephemeral Riverpod state, `dragStateProvider`
(`NotifierProvider<DragNotifier, DragState?>`, `null` when idle), holds:

- `block` — the `TimeObject` being moved, and `originalDate`
- `targetDate`, `targetStart` — the current snapped landzone position
- `pointerGlobalPosition` — for edge-zone detection

Flow:

1. A drag starts on a block (see Gesture handling) → `DragNotifier.start(block, originalDate)`.
2. As the pointer moves, the `DayGrid` column currently under the pointer
   converts the local position to a snapped time via the existing
   `slotStartForOffset` helper (already used for new-block drafts) and calls
   `DragNotifier.updateTarget(date, start, globalPosition)`. Which column is
   "current" is resolved from each visible column's screen `Rect`, known to
   `_SchedulePage` at layout time.
3. Every currently-built `DayGrid` watches `dragStateProvider`. If
   `targetDate` matches its own `date`, it renders the landzone shadow at
   `targetStart`, sized to the dragged block's duration. The origin column
   additionally hides/dims the real block being dragged.
4. `DayScreen` watches the same provider's `pointerGlobalPosition` to drive
   edge-triggered paging (see below).
5. On release, `DragNotifier` calls the repository's new `move` operation,
   then clears state to `null`.

This avoids threading drag callbacks through `PageView`'s lazily-built pages —
any column that happens to be built can react to the shared provider directly.

## Gesture handling

Blocks currently absorb no gestures — taps on them fall through the `Stack` to
the grid's own `GestureDetector`, which only dismisses an open draft. Each
non-locked block gets its own opaque `GestureDetector`/`RawGestureDetector` so
it fully owns any gesture starting within its bounds:

- **Touch** (`PointerDeviceKind.touch`): a `LongPressGestureRecognizer` —
  `onLongPressStart` begins the drag, `onLongPressMoveUpdate` feeds position
  updates, `onLongPressEnd` drops it.
- **Mouse/trackpad** (`PointerDeviceKind.mouse`/`trackpad`): a
  `PanGestureRecognizer` — `onPanStart` begins the drag immediately (no hold
  delay), `onPanUpdate`/`onPanEnd` follow.
- **Plain tap** (no hold, no movement): calls back to `DayGrid` to dismiss any
  open draft, preserving today's incidental behavior.
- **Locked blocks** only wire the tap-to-dismiss handler — no drag
  recognizers.

Because the block now claims any pointer starting inside it, the grid's
existing `onLongPressStart`/`onDoubleTapDown` (new-block draft) handlers are
unaffected — they only ever see pointers starting on genuinely empty space.

## Landzone rendering

Visually similar to the existing `_DraftOverlay`'s dashed box, but simpler — a
translucent outline sized to the block's duration, no buttons. Renders at
`targetStart` in whichever column matches `targetDate`, with no exclusion
zones: it renders at any snapped target, including directly over the block's
own original spot (which is safe since the real block is hidden there while
dragging) or over other existing blocks.

## Edge-triggered paging

`DayScreen` watches `dragStateProvider.pointerGlobalPosition`. When it falls
within the existing edge-zone width (`_edgeFadeWidth`, 72px) near the left or
right screen edge, a ~600ms dwell timer starts; if the pointer is still in the
zone when it fires, `DayScreen` calls the existing `_animateBy(±1)` to page to
the adjacent day/week, then restarts the timer for continuous paging while
held. Leaving the zone cancels the pending timer. Reuses `_animateBy` as-is —
no changes to the paging animation.

## Commit on drop

`DayBlocksRepository` gains:

```dart
Future<TimeObject> move(
  TimeObject block, {
  required DateTime fromDate,
  required DateTime toDate,
  required DateTime newStart,
  required DateTime newEnd,
});
```

`InMemoryDayBlocksRepository.move` removes the block from `_added[fromDate]`
and adds the updated block under `_added[toDate]`. A seeded block (not yet in
`_added`) being moved for the first time is promoted into `_added` under its
new date/time, and implicitly excluded from `_seedFor`'s output for its
original date going forward (seeded blocks are keyed by id; once an id has
been moved, `_seedFor` must skip it).

On drop, `DragNotifier` calls `move`, invalidates/refetches both
`dayBlocksProvider(fromDate)` and `dayBlocksProvider(toDate)`, then clears
drag state to `null`.

Dropping outside any valid day column (e.g. over the header) cancels the
move — state clears without calling `move`; the block stays where it was.

## Testing

- Widget tests (extending the existing pattern used for long-press/
  double-tap draft creation) drive the new recognizers directly to verify:
  landzone appears on the correct column at the correct snapped time; locked
  blocks ignore drag gestures; drop calls `move` with the right arguments;
  edge-dwell triggers `_animateBy`.
- E2E: `e2e/tests/support/gestures.ts` already has drag/swipe helpers: add a
  cross-day drag scenario exercising the edge-transition path.
