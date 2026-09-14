# Pinned Search Views

Date: 2026-09-14

## Summary

Allow users to pin (star) a search query on the Tasks screen. Pinned
queries ("saved views") are persisted, shown as a list in the sidebar
directly under the "Tasks" nav destination, can be renamed, deleted,
and reordered by drag, and clicking one loads that query back into the
Tasks search bar.

## Goals / Non-goals

- Goal: persist arbitrary search query strings under a user-editable
  name, list them in the sidebar, let the user jump back into any of
  them.
- Goal: reordering of the saved-views list, following the same
  persisted `order` field pattern already used by tasks/categories.
- Non-goal: changes to the search query engine itself
  (`search_query.dart` is untouched — a saved view is just a stored
  string).
- Non-goal: saved views for any screen other than Tasks.
- Non-goal: sharing/exporting views, folders/nesting, or any
  view-level settings beyond the query text and name.

## Data model & persistence

New feature module `lib/features/saved_search/`, mirroring the shape
of `lib/features/category/`:

- `models/saved_search.dart`:
  ```dart
  class SavedSearch {
    final String id;
    final String name;   // e.g. "Tasks view 2"
    final String query;  // raw search text, e.g. "#urgent /work foo"
    final int order;
  }
  ```
- `data/saved_search_repository.dart`: abstract
  `SavedSearchRepository` (`loadAll`, `add`, `update`, `delete`,
  `reorder`) with `InMemorySavedSearchRepository` and
  `SembastSavedSearchRepository` implementations, following the
  existing dual-implementation pattern used by
  `TaskRepository`/category repo.
- New `savedSearchesStore` `StoreRef` added to
  `lib/core/storage/app_database.dart`, alongside the existing
  `tasksStore`/`categoriesStore`/etc. Records are sorted by `order`
  via `Finder(sortOrders: [SortOrder('order')])`, same as categories.
- `providers.dart`: `savedSearchRepositoryProvider` (swappable
  backing store, overridden in `main.dart` same as other
  repositories) and `SavedSearchListNotifier extends
  AsyncNotifier<List<SavedSearch>>` (`savedSearchListProvider`)
  exposing:
  - `addView(String query)` — computes default name as `Tasks view
    ${existingCount + 1}` (count-based, not an ever-increasing
    counter — reusing a number after deletions is acceptable), calls
    repository `add`, updates `state`.
  - `renameView(String id, String newName)`
  - `deleteView(String id)`
  - `reorder(int oldIndex, int newIndex)` — recomputes and persists
    `order` for the affected range, mirroring how categories persist
    reordering today (even though no UI currently drives that for
    categories).

## Search bar: star icon

In `lib/features/task/widgets/tasks_screen.dart`, add a star
`IconButton` to the search `TextField`'s `suffixIcon`, positioned
immediately after the existing `filter_alt` icon button.

- State: watches `savedSearchListProvider`; on every change to the
  query controller's text (same place `_syncUrl()` already runs),
  recompute whether `list.any((v) => v.query ==
  controller.text.trim())`.
- Empty query text → star is hidden/disabled (nothing meaningful to
  pin).
- Not matched → star renders outlined. Tap → `addView(currentQuery)`.
- Matched → star renders filled/solid. Tap → look up the matching
  `SavedSearch` by query text and `deleteView(it.id)`.
- Loading a saved view from the sidebar (below) does **not** create
  any live binding between the search box and that view. If the user
  edits the text afterward, the star simply goes back to whatever
  state matches the new text (usually outlined, since it's now an
  unsaved variant) — the original saved view is left untouched. There
  is no "currently active view" concept to track or clear.

## Sidebar: saved views list

In `lib/core/widgets/app_shell.dart`, add a "Saved views" section
directly under the "Tasks" destination, in both the wide (persistent)
sidebar and the narrow `Drawer`. The section (header + rows) is only
rendered when `savedSearchListProvider` is non-empty.

Each row shows the view's name and, on tap, navigates via
`context.go('/tasks?q=${Uri.encodeQueryComponent(view.query)}')`
(consistent with the existing URL-param round-trip already used for
search state).

**Desktop (wide sidebar, mouse/hover available):**
- Default: row shows just the name.
- On hover: a trailing overflow (⋮) icon button appears (Rename /
  Delete menu) and a leading drag-handle icon appears.
- Drag handle wraps `ReorderableDragStartListener` so a plain tap/click
  never triggers a drag — only a press-and-drag from the handle does.

**Narrow (drawer, touch):**
- Default: row shows just the name.
- Long-press a row: toggles a temporary "revealed" state on that row
  (local widget state, not persisted) showing the same ⋮ menu and drag
  handle. Tapping elsewhere or completing an action collapses it back.
- This is the same `ReorderableListView` / drag-handle mechanism as
  desktop — only the trigger for revealing the affordances differs.

**Rename:**
⋮ menu → "Rename" swaps the row's `Text` label for an inline
`TextField` pre-filled with the current name, autofocused. Submits on
enter or on blur, calling `renameView(id, newText)`. Empty name is
rejected (revert to previous name).

**Delete:**
⋮ menu → "Delete" calls `deleteView(id)` directly (no confirmation
dialog — consistent with how lightweight this action is; deleting is
symmetric with un-starring from the search bar).

**Reorder:**
The saved-views list is wrapped in Flutter's built-in
`ReorderableListView` (unused elsewhere in the app currently, but a
better fit here than the hand-rolled 2D drag system built for the day
grid, since this is a simple 1D vertical list). `onReorder` calls
`SavedSearchListNotifier.reorder(oldIndex, newIndex)`.

## Testing

- Unit tests for `SavedSearchListNotifier`: add computes correct
  default name and appends; rename updates name; delete removes by
  id; reorder persists new `order` values — all against
  `InMemorySavedSearchRepository`.
- Widget tests:
  - Star icon reflects outlined/filled state as the search text
    changes to match/not match an existing saved view; tapping
    creates/deletes accordingly.
  - Sidebar renders a "Saved views" section under Tasks only when
    views exist; tapping a view navigates and prefills the search bar
    with its query.
  - Rename flow: opening the ⋮ menu, editing, and submitting updates
    the displayed name.
  - Reorder flow: dragging a row via `ReorderableListView`'s drag
    mechanics updates list order.

## Out of scope / explicitly deferred

- No confirmation dialog on delete.
- No limit on number of saved views.
- No dedupe — a user can end up with two saved views sharing the same
  query text (e.g. after renaming), which is fine; the star's
  matched/unmatched state just reflects whether *any* view has that
  exact query.
