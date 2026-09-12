# Tasks engine (stage 1: flat task list)

## Purpose

Tasks are a new, simpler kind of item alongside the day/template schedule
blocks: a title, an open/closed state, and an optional category — with no
time-of-day, no drag/resize, no grid. This is stage 1: a new `/tasks` path
listing every task, with add/close/edit/delete. Anything beyond a flat
list (grouping, filtering, sorting, reordering, converting a task into a
schedule block) is future work.

## Scope

In scope:
- A `Task` model and repository (in-memory + sembast-backed), independent
  of dates/templates
- `TasksScreen`: a new top-level nav destination showing every task as a
  card in creation order
- Closing a task inline from its card; editing a task (title, category,
  closed) in a modal; deleting a task from that modal
- Reusing the existing category-assignment picker and the existing
  color/emoji card styling (see Decisions)
- Tests for the new model/repository/provider and for `TasksScreen`

Out of scope:
- Grouping/sorting beyond creation order, filtering closed tasks out of
  view, reordering
- Assigning a due date/time, converting a task into a schedule block, or
  any relationship between tasks and day/template blocks
- Any nav placement decision beyond appending as a fourth destination

## Decisions

- **`Task` is a new, independent model** (`lib/features/task/models/
  task.dart`), not a variant of `TimeObject` — it has no `start`/`end`/
  `kind`/`locked`, so forcing it into `TimeObject`'s shape would mean
  nullable time fields rippling through every place that already assumes
  a block has a time. `Task` only carries `id`, `title`, `closed` (default
  `false`), and `categoryId` (default `Category.defaultId`, exactly like
  `TimeObject`).
- **Storage mirrors the category feature's shape**, not the day feature's:
  a single flat `TaskRepository` (`load`, `add`, `update`, `delete`), no
  date/template-keyed filtering, no `deleteAll`. New `tasksStore` in
  `app_database.dart`. `InMemoryTaskRepository` for tests, plus a
  `SembastTaskRepository` for real persistence — tasks are meant to
  persist across restarts as a first-class list, unlike the day feature's
  in-memory seed data.
- **`BlockCategoryPicker` moves from `lib/features/day/widgets/
  block_edit_modal.dart` to `lib/features/category/widgets/
  category_picker.dart`.** It's pure category-assignment UI (a
  `selectedCategoryId`/`onSelected` pair, no knowledge of blocks or time)
  that both the day feature and the new task feature need. Moving it into
  the category feature avoids a day↔task dependency in either direction.
  This is a relocation only — no behavior change — and the day feature's
  one call site is updated to the new import.
- **No new shared "colored card" widget.** `BlockView`'s two relevant
  lines — `Color(category.colorValue)` as fill and
  `category.formatTitle(title)` for the emoji-prefixed label — are
  inlined directly into a new `TaskCard`. `BlockView` also encodes
  anchor/frame-specific chrome (filled vs outlined, optional title
  overlay) that doesn't apply to a task card, so extracting a shared base
  widget would only add an abstraction neither side fully uses.
- **Closing is a one-tap affordance on the card itself** (a checkbox/
  checkmark leading the title), separate from opening the edit modal —
  matching the request that closing not require opening a modal. The
  modal also exposes closed as a toggle, so it can be flipped from either
  place.
- **List order is pure creation order** (repository/store order), same
  choice already made for templates and categories. Closed tasks stay in
  place in that order, shown with a struck-through/dimmed title rather
  than moved or hidden.

## Data model

```dart
// lib/features/task/models/task.dart
class Task {
  const Task({
    required this.id,
    required this.title,
    this.closed = false,
    this.categoryId = Category.defaultId,
  });

  factory Task.fromMap(Map<String, Object?> map) => Task(
    id: map['id']! as String,
    title: map['title']! as String,
    closed: map['closed']! as bool,
    categoryId: map['categoryId']! as String,
  );

  final String id;
  final String title;
  final bool closed;
  final String categoryId;

  Task copyWith({String? title, bool? closed, String? categoryId}) => Task(
    id: id,
    title: title ?? this.title,
    closed: closed ?? this.closed,
    categoryId: categoryId ?? this.categoryId,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'closed': closed,
    'categoryId': categoryId,
  };
}
```

`TaskRepository` mirrors `CategoryRepository`'s shape:

```dart
abstract class TaskRepository {
  Future<List<Task>> load();
  Future<Task> add({required String title, String? categoryId});
  Future<Task> update(Task task, {String? title, bool? closed, String? categoryId});
  Future<void> delete(Task task);
}
```

`InMemoryTaskRepository` keeps an ordered `List<Task>`, mirroring
`InMemoryCategoryRepository`. `SembastTaskRepository` writes/reads
`tasksStore` records keyed by task id, mirroring
`SembastCategoryRepository` (an `order` field preserves creation order
the same way categories/templates already do).

`taskRepositoryProvider` + `TaskListNotifier`/`taskListProvider`
(`AsyncNotifier<List<Task>>` with `addTask`/`updateTask`/`deleteTask`)
mirror `categoryRepositoryProvider`/`CategoryListNotifier` exactly.

## Routing and navigation

`/tasks` becomes a fourth `StatefulShellRoute` branch in
`lib/router.dart`, alongside `/` (Day), `/templates`, and `/categories`.
`AppShell`'s `_destinations` gets a fourth entry, "Tasks" (e.g.
`Icons.check_circle_outline`), appended after "Categories" so branch
order and destination order stay in lockstep as they already do for the
other three.

## `TasksScreen`

A `ConsumerWidget` watching `taskListProvider`, structurally close to
`CategoriesScreen`: an `AppBar` titled "Tasks" with an "Add task" `+`
action opening `TaskEditModal` in create mode, and a `ListView` of
`TaskCard`s in list order (same narrow/wide centered-card wrapping
`CategoriesScreen` already does at `narrowBreakpoint`).

`TaskCard`:
- Filled container using `Color(category.colorValue)` as background
  (falling back to the theme's `primaryContainer` while categories are
  still loading, matching `BlockView`'s fallback) and
  `category.formatTitle(task.title)` as the label, struck-through/dimmed
  when `task.closed`.
- A leading checkbox reflecting `task.closed`, toggling it directly via
  `taskListProvider.notifier.updateTask(task, closed: !task.closed)` —
  no modal round-trip needed just to close a task.
- Tapping the rest of the card opens `TaskEditModal` in edit mode.

`TaskEditModal` (`lib/features/task/widgets/task_edit_modal.dart`):
responsive shell identical to `showCategoryEditSheet` (bottom sheet
narrow / centered dialog wide). Fields: title `TextField`,
`BlockCategoryPicker` (now in the category feature) bound to
`categoryId`, a "Closed" `Switch`. Actions: Cancel, Save (disabled when
title is empty, matching `category_edit_sheet`'s save-guard), and — edit
mode only — Delete (confirmation dialog matching `CategoriesScreen`'s
`_confirmDelete`, then `taskListProvider.notifier.deleteTask(task)` and
pop).

## Testing

- Unit tests: `Task.toMap`/`fromMap` round-trip; `InMemoryTaskRepository`
  (add/update/delete/load ordering); `TaskListNotifier` (add/update/
  delete against a fake repository), mirroring the existing category
  repository/provider tests.
- Widget tests: `tasks_screen_test.dart` — add a task, toggle closed from
  the card, edit a task's title/category via the modal, delete a task,
  confirming list order is preserved throughout. A `category_picker_test.dart`
  (renamed/moved from wherever `BlockCategoryPicker` is currently tested,
  if it is) confirms the move didn't change behavior.
- Regression: existing `day_screen_test.dart`/`block_edit_modal` tests
  must keep passing unchanged after `BlockCategoryPicker` moves — only
  its import path changes.

## Future work (not this stage)

Grouping/sorting the task list by category or closed state, filtering
closed tasks out of view, reordering, due dates, and any link between a
task and a schedule block (e.g. "schedule this task" creating a
`TimeObject`) are all future stages. Nothing in this design precludes
them, but no UI or code for them exists yet.
