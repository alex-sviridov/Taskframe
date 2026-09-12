# Tasks Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new "Tasks" section to the app — a `/tasks` nav destination listing all tasks (title, open/closed, optional category), with inline closing, an edit/delete modal, and sembast persistence — reusing the app's existing category-assignment and color/emoji styling logic.

**Architecture:** A new `lib/features/task/` feature (model, repository pair, Riverpod provider, three widgets) mirroring the existing `category` feature's shape almost exactly (flat list, no date/template keying). One existing widget, `BlockCategoryPicker`, is relocated from the `day` feature into the `category` feature so both `day` and `task` can depend on it without depending on each other. Routing/nav gain a fourth branch/destination.

**Tech Stack:** Flutter, `flutter_riverpod` (AsyncNotifier), `sembast` (persistence), `go_router` (`StatefulShellRoute`), `flutter_test`/`sembast_memory` for tests.

**Spec:** `docs/superpowers/specs/2026-09-12-tasks-engine-design.md`

## Global Constraints

- This codebase's constructor convention: an unnamed constructor is written `new(...)` (not `ClassName(...)`), e.g. `const new({required this.id, ...})` or `new(this._db)`. Follow this exactly in every new class — it is not a typo.
- Every new repository pair follows the existing `category`/`template` shape: an abstract interface + `InMemory*` (default, used by every existing test's bare `ProviderContainer()`) + `Sembast*` (wired in only at `main.dart`/`sembast_overrides.dart`).
- `Task.categoryId` defaults to `Category.defaultId`, matching `TimeObject.categoryId`.
- List order everywhere is creation/insertion order — no sort field, no reordering.
- Run `flutter test` after every task; the whole suite must stay green (this plan touches a shared widget, `BlockCategoryPicker`, so regressions in `day`/`template` tests are the main risk to watch for).

---

### Task 1: `Task` model

**Files:**
- Create: `lib/features/task/models/task.dart`
- Test: `test/unit/task_test.dart`

**Interfaces:**
- Produces: `Task` class — `Task({required String id, required String title, bool closed = false, String categoryId = Category.defaultId})`, `Task.fromMap(Map<String, Object?>)`, `.toMap()`, `.copyWith({String? title, bool? closed, String? categoryId})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/task_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/models/task.dart';

void main() {
  group('Task', () {
    test('closed defaults to false', () {
      const task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.closed, isFalse);
    });

    test('categoryId defaults to Category.defaultId', () {
      const task = Task(id: 'task-1', title: 'Buy milk');

      expect(task.categoryId, Category.defaultId);
    });

    test('copyWith replaces only the given fields', () {
      const task = Task(
        id: 'task-1',
        title: 'Buy milk',
        closed: false,
        categoryId: 'category-1',
      );

      final updated = task.copyWith(title: 'Buy oat milk', closed: true);

      expect(updated.id, 'task-1');
      expect(updated.title, 'Buy oat milk');
      expect(updated.closed, isTrue);
      expect(updated.categoryId, 'category-1');
    });

    test('copyWith with no arguments returns equivalent fields', () {
      const task = Task(
        id: 'task-1',
        title: 'Buy milk',
        closed: true,
        categoryId: 'category-1',
      );

      final copy = task.copyWith();

      expect(copy.id, task.id);
      expect(copy.title, task.title);
      expect(copy.closed, task.closed);
      expect(copy.categoryId, task.categoryId);
    });
  });

  group('toMap/fromMap', () {
    test('fromMap(toMap()) round-trips every field', () {
      const task = Task(
        id: 'task-1',
        title: 'Buy milk',
        closed: true,
        categoryId: 'category-1',
      );

      final restored = Task.fromMap(task.toMap());

      expect(restored.id, task.id);
      expect(restored.title, task.title);
      expect(restored.closed, task.closed);
      expect(restored.categoryId, task.categoryId);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/task_test.dart`
Expected: FAIL — `lib/features/task/models/task.dart` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/task/models/task.dart
import 'package:taskframe/features/category/models/category.dart';

/// A single task: a title, whether it's closed, and an optional category.
/// Unlike a [Category]-tagged schedule block, a task has no time-of-day —
/// it's a flat, unordered-by-time item.
class Task {
  /// Creates a [Task].
  const new({
    required this.id,
    required this.title,
    this.closed = false,
    this.categoryId = Category.defaultId,
  });

  /// Reconstructs a [Task] from a map produced by [toMap].
  factory fromMap(Map<String, Object?> map) => Task(
    id: map['id']! as String,
    title: map['title']! as String,
    closed: map['closed']! as bool,
    categoryId: map['categoryId']! as String,
  );

  /// Unique identifier for this task.
  final String id;

  /// The task's title.
  final String title;

  /// Whether this task has been closed (marked done). Defaults to `false`.
  final bool closed;

  /// The id of the [Category] this task is tagged with. Defaults to
  /// [Category.defaultId], so every task always resolves to some category.
  final String categoryId;

  /// Returns a copy of this task with any of [title]/[closed]/[categoryId]
  /// replaced.
  Task copyWith({String? title, bool? closed, String? categoryId}) => Task(
    id: id,
    title: title ?? this.title,
    closed: closed ?? this.closed,
    categoryId: categoryId ?? this.categoryId,
  );

  /// This task's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'closed': closed,
    'categoryId': categoryId,
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/task_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/task/models/task.dart test/unit/task_test.dart
git commit -m "Add Task model"
```

---

### Task 2: `TaskRepository` + `InMemoryTaskRepository`

**Files:**
- Create: `lib/features/task/data/task_repository.dart`
- Test: `test/unit/task_repository_test.dart`

**Interfaces:**
- Consumes: `Task` (Task 1).
- Produces: `abstract class TaskRepository { Future<List<Task>> load(); Future<Task> add({required String title, String? categoryId}); Future<Task> update(Task task, {String? title, bool? closed, String? categoryId}); Future<void> delete(Task task); }`; `class InMemoryTaskRepository implements TaskRepository`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/task_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/data/task_repository.dart';

void main() {
  group('InMemoryTaskRepository', () {
    late InMemoryTaskRepository repository;

    setUp(() => repository = InMemoryTaskRepository());

    test('load starts empty', () async {
      expect(await repository.load(), isEmpty);
    });

    test('add appends a new open task with the default category', () async {
      final added = await repository.add(title: 'Buy milk');

      expect(added.title, 'Buy milk');
      expect(added.closed, isFalse);
      expect(added.categoryId, Category.defaultId);
    });

    test('add accepts an explicit categoryId', () async {
      final added = await repository.add(
        title: 'Buy milk',
        categoryId: 'category-1',
      );

      expect(added.categoryId, 'category-1');
    });

    test('two added tasks get distinct ids', () async {
      final first = await repository.add(title: 'First');
      final second = await repository.add(title: 'Second');

      expect(first.id, isNot(equals(second.id)));
    });

    test('added tasks show up in a later load, in creation order', () async {
      await repository.add(title: 'First');
      await repository.add(title: 'Second');

      final tasks = await repository.load();

      expect(tasks.map((t) => t.title), ['First', 'Second']);
    });

    test('update changes title/closed/categoryId', () async {
      final added = await repository.add(title: 'Buy milk');

      final updated = await repository.update(
        added,
        title: 'Buy oat milk',
        closed: true,
        categoryId: 'category-1',
      );

      expect(updated.id, added.id);
      expect(updated.title, 'Buy oat milk');
      expect(updated.closed, isTrue);
      expect(updated.categoryId, 'category-1');
    });

    test('update leaves fields unspecified as null unchanged', () async {
      final added = await repository.add(
        title: 'Buy milk',
        categoryId: 'category-1',
      );

      final updated = await repository.update(added, closed: true);

      expect(updated.title, 'Buy milk');
      expect(updated.categoryId, 'category-1');
    });

    test('update replaces the task in a later load', () async {
      final added = await repository.add(title: 'Buy milk');

      await repository.update(added, title: 'Buy oat milk');

      final tasks = await repository.load();
      expect(tasks.singleWhere((t) => t.id == added.id).title, 'Buy oat milk');
    });

    test('delete removes a task from a later load', () async {
      final added = await repository.add(title: 'Buy milk');

      await repository.delete(added);

      final tasks = await repository.load();
      expect(tasks.where((t) => t.id == added.id), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/task_repository_test.dart`
Expected: FAIL — `lib/features/task/data/task_repository.dart` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/task/data/task_repository.dart
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/models/task.dart';

/// Loads and stores the flat list of tasks.
///
/// Implementations back this with whatever storage is appropriate (in
/// memory today, sembast for real persistence); callers depend only on
/// this interface.
abstract class TaskRepository {
  /// Returns every task, in creation order.
  Future<List<Task>> load();

  /// Creates a new, open task and returns it. [categoryId] defaults to
  /// [Category.defaultId] when omitted.
  Future<Task> add({required String title, String? categoryId});

  /// Updates [task] in place, replacing any of [title]/[closed]/
  /// [categoryId] that are given and leaving the rest unchanged. Returns
  /// the updated task.
  Future<Task> update(
    Task task, {
    String? title,
    bool? closed,
    String? categoryId,
  });

  /// Removes [task].
  Future<void> delete(Task task);
}

/// A [TaskRepository] that keeps tasks in memory for the life of the app,
/// starting empty.
class InMemoryTaskRepository implements TaskRepository {
  final List<Task> _tasks = [];
  int _nextId = 0;

  @override
  Future<List<Task>> load() async => List.unmodifiable(_tasks);

  @override
  Future<Task> add({required String title, String? categoryId}) async {
    final task = Task(
      id: 'task-${_nextId++}',
      title: title,
      categoryId: categoryId ?? Category.defaultId,
    );
    _tasks.add(task);
    return task;
  }

  @override
  Future<Task> update(
    Task task, {
    String? title,
    bool? closed,
    String? categoryId,
  }) async {
    final updated = task.copyWith(
      title: title,
      closed: closed,
      categoryId: categoryId,
    );
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index == -1) {
      throw StateError('Task ${task.id} not found');
    }
    _tasks[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(Task task) async {
    _tasks.removeWhere((t) => t.id == task.id);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/task_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/task/data/task_repository.dart test/unit/task_repository_test.dart
git commit -m "Add TaskRepository and InMemoryTaskRepository"
```

---

### Task 3: `tasksStore` + `SembastTaskRepository`

**Files:**
- Modify: `lib/core/storage/app_database.dart`
- Create: `lib/features/task/data/sembast_task_repository.dart`
- Test: `test/unit/sembast_task_repository_test.dart`

**Interfaces:**
- Consumes: `Task`, `TaskRepository` (Tasks 1–2).
- Produces: `tasksStore` (`StoreRef<String, Map<String, Object?>>`); `class SembastTaskRepository implements TaskRepository`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/sembast_task_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/data/sembast_task_repository.dart';

void main() {
  group('SembastTaskRepository', () {
    late SembastTaskRepository repository;

    setUp(() async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastTaskRepository(db);
    });

    test('load starts empty', () async {
      expect(await repository.load(), isEmpty);
    });

    test('add appends a new open task with the default category', () async {
      final added = await repository.add(title: 'Buy milk');

      expect(added.closed, isFalse);
      expect(added.categoryId, Category.defaultId);
      final tasks = await repository.load();
      expect(tasks, hasLength(1));
    });

    test('two added tasks get distinct ids', () async {
      final first = await repository.add(title: 'First');
      final second = await repository.add(title: 'Second');

      expect(first.id, isNot(second.id));
    });

    test('added tasks load back in creation order', () async {
      await repository.add(title: 'First');
      await repository.add(title: 'Second');

      final tasks = await repository.load();

      expect(tasks.map((t) => t.title), ['First', 'Second']);
    });

    test('update changes title/closed/categoryId', () async {
      final added = await repository.add(title: 'Buy milk');

      final updated = await repository.update(
        added,
        title: 'Buy oat milk',
        closed: true,
        categoryId: 'category-1',
      );

      expect(updated.title, 'Buy oat milk');
      expect(updated.closed, isTrue);
      expect(updated.categoryId, 'category-1');
    });

    test('update leaves fields unspecified as null unchanged', () async {
      final added = await repository.add(
        title: 'Buy milk',
        categoryId: 'category-1',
      );

      final updated = await repository.update(added, closed: true);

      expect(updated.title, 'Buy milk');
      expect(updated.categoryId, 'category-1');
    });

    test('update replaces the task in a later load', () async {
      final added = await repository.add(title: 'Buy milk');

      await repository.update(added, title: 'Buy oat milk');

      final tasks = await repository.load();
      expect(tasks.singleWhere((t) => t.id == added.id).title, 'Buy oat milk');
    });

    test('delete removes a task from a later load', () async {
      final added = await repository.add(title: 'Buy milk');

      await repository.delete(added);

      final tasks = await repository.load();
      expect(tasks.where((t) => t.id == added.id), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/sembast_task_repository_test.dart`
Expected: FAIL — `lib/features/task/data/sembast_task_repository.dart` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

Add to `lib/core/storage/app_database.dart`, right after `categoriesStore`:

```dart
/// Tasks, keyed by task id, each record carrying an `order` field that
/// preserves creation order.
final StoreRef<String, Map<String, Object?>> tasksStore =
    stringMapStoreFactory.store('tasks');
```

```dart
// lib/features/task/data/sembast_task_repository.dart
import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/task/data/task_repository.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A [TaskRepository] backed by a sembast [Database], persisting tasks
/// across restarts. Records are keyed by [Task.id]; an `order` field (set
/// once at creation) keeps [load] in creation order.
class SembastTaskRepository implements TaskRepository {
  /// Creates a [SembastTaskRepository] reading/writing [_db].
  new(this._db);

  final Database _db;

  @override
  Future<List<Task>> load() async {
    final finder = Finder(sortOrders: [SortOrder('order')]);
    final records = await tasksStore.find(_db, finder: finder);
    return [for (final record in records) Task.fromMap(record.value)];
  }

  @override
  Future<Task> add({required String title, String? categoryId}) async {
    final task = Task(
      id: _uuid.v4(),
      title: title,
      categoryId: categoryId ?? Category.defaultId,
    );
    await tasksStore.record(task.id).put(_db, {
      ...task.toMap(),
      'order': DateTime.now().microsecondsSinceEpoch,
    });
    return task;
  }

  @override
  Future<Task> update(
    Task task, {
    String? title,
    bool? closed,
    String? categoryId,
  }) async {
    final existingRecord = await tasksStore.record(task.id).get(_db);
    final current = existingRecord == null ? task : Task.fromMap(existingRecord);
    final updated = current.copyWith(
      title: title,
      closed: closed,
      categoryId: categoryId,
    );
    final order =
        existingRecord?['order'] ?? DateTime.now().microsecondsSinceEpoch;
    await tasksStore.record(updated.id).put(_db, {
      ...updated.toMap(),
      'order': order,
    });
    return updated;
  }

  @override
  Future<void> delete(Task task) async {
    await tasksStore.record(task.id).delete(_db);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/sembast_task_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/storage/app_database.dart lib/features/task/data/sembast_task_repository.dart test/unit/sembast_task_repository_test.dart
git commit -m "Add tasksStore and SembastTaskRepository"
```

---

### Task 4: Task providers

**Files:**
- Create: `lib/features/task/providers.dart`
- Test: `test/unit/task_providers_test.dart`

**Interfaces:**
- Consumes: `Task`, `TaskRepository`, `InMemoryTaskRepository` (Tasks 1–2).
- Produces: `taskRepositoryProvider` (`Provider<TaskRepository>`); `class TaskListNotifier extends AsyncNotifier<List<Task>>` with `addTask({required String title, String? categoryId})`, `updateTask(Task task, {String? title, bool? closed, String? categoryId})`, `deleteTask(Task task)`; `taskListProvider` (`AsyncNotifierProvider<TaskListNotifier, List<Task>>`).

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/task_providers_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/task/data/task_repository.dart';
import 'package:taskframe/features/task/providers.dart';

void main() {
  group('taskListProvider', () {
    test('loads the repository tasks (empty to start)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final tasks = await container.read(taskListProvider.future);
      final expected = await InMemoryTaskRepository().load();

      expect(tasks.map((t) => t.id), expected.map((t) => t.id));
    });

    test('addTask appends the new task returned by the repository', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(taskListProvider.future);

      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.where((t) => t.title == 'Buy milk'), hasLength(1));
    });

    test('addTask returns the created task', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(taskListProvider.future);

      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk', categoryId: 'category-1');

      expect(created.title, 'Buy milk');
      expect(created.categoryId, 'category-1');
    });

    test('updateTask persists a title/closed/category change', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(taskListProvider.future);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');

      await container
          .read(taskListProvider.notifier)
          .updateTask(created, title: 'Buy oat milk', closed: true);

      final tasks = container.read(taskListProvider).value!;
      final updated = tasks.singleWhere((t) => t.id == created.id);
      expect(updated.title, 'Buy oat milk');
      expect(updated.closed, isTrue);
    });

    test('deleteTask removes the task from state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(taskListProvider.future);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');

      await container.read(taskListProvider.notifier).deleteTask(created);

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.where((t) => t.id == created.id), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/task_providers_test.dart`
Expected: FAIL — `lib/features/task/providers.dart` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/task/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/task/data/task_repository.dart';
import 'package:taskframe/features/task/models/task.dart';

/// The backing store for tasks.
///
/// Overriding this single provider (e.g. with the sembast-backed
/// implementation) is enough to change where tasks are loaded from and
/// saved to; nothing downstream needs to change.
final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => InMemoryTaskRepository(),
);

/// Holds the list of tasks, loaded from [taskRepositoryProvider], and
/// lets consumers add/update/delete them.
class TaskListNotifier extends AsyncNotifier<List<Task>> {
  @override
  Future<List<Task>> build() => ref.watch(taskRepositoryProvider).load();

  /// Creates a new task, adds it to the current state, and returns it.
  Future<Task> addTask({required String title, String? categoryId}) async {
    final repository = ref.read(taskRepositoryProvider);
    final added = await repository.add(title: title, categoryId: categoryId);
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Updates [task]'s title/closed/category, persisting via the
  /// repository and refreshing state.
  Future<void> updateTask(
    Task task, {
    String? title,
    bool? closed,
    String? categoryId,
  }) async {
    final repository = ref.read(taskRepositoryProvider);
    final updated = await repository.update(
      task,
      title: title,
      closed: closed,
      categoryId: categoryId,
    );
    state = AsyncData([
      for (final t in state.value ?? <Task>[])
        if (t.id == task.id) updated else t,
    ]);
  }

  /// Removes [task], persisting via the repository and refreshing state.
  Future<void> deleteTask(Task task) async {
    final repository = ref.read(taskRepositoryProvider);
    await repository.delete(task);
    state = AsyncData([
      for (final t in state.value ?? <Task>[])
        if (t.id != task.id) t,
    ]);
  }
}

/// The list of tasks.
final taskListProvider = AsyncNotifierProvider<TaskListNotifier, List<Task>>(
  TaskListNotifier.new,
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/task_providers_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/task/providers.dart test/unit/task_providers_test.dart
git commit -m "Add task providers"
```

---

### Task 5: Relocate `BlockCategoryPicker` into the category feature

**Files:**
- Create: `lib/features/category/widgets/category_picker.dart`
- Modify: `lib/features/day/widgets/block_edit_modal.dart` (remove `BlockCategoryPicker`/`_CategoryRow`/`_fieldDecoration`, import the new location instead)
- Create: `test/widget/category_picker_test.dart`
- Modify: `test/widget/block_edit_modal_test.dart` (remove the `group('BlockCategoryPicker', ...)` block and its `_pumpPicker`/`_useNarrowView` helpers if no longer used elsewhere in that file, update imports)

**Interfaces:**
- Produces: `BlockCategoryPicker` (unchanged public API — `selectedCategoryId`, `onSelected`), now importable from `package:taskframe/features/category/widgets/category_picker.dart`.
- Consumes: `Category`, `categoryListProvider`, `categoryById` (existing `category` feature exports); `isNarrow` from `lib/core/responsive.dart`.

This is a pure relocation — no behavior change — so it's TDD'd as "move the test, watch it pass against the moved code" rather than red/green from scratch.

- [ ] **Step 1: Read the current `BlockCategoryPicker` implementation and its private helpers**

Open `lib/features/day/widgets/block_edit_modal.dart` and locate `_CategoryRow`, `_fieldDecoration`, and `BlockCategoryPicker` (roughly the first ~140 lines of the file, ending just before `BlockTimeRow`). Confirm nothing else in that file references `_CategoryRow` or `_fieldDecoration` before removing them (only `BlockTimeRow`'s own `formatHm` import and later classes are unrelated).

- [ ] **Step 2: Create the new file with the relocated code**

```dart
// lib/features/category/widgets/category_picker.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';

/// A small color dot for [category] followed by its emoji-prefixed name,
/// used for every row of [BlockCategoryPicker] — the closed field, its
/// dropdown menu items, and its wheel entries alike — so they never drift
/// out of visual sync with each other. Color is an accent (a swatch), not
/// the row's whole background, so it reads as a standard field/menu row
/// rather than a colored block.
class _CategoryRow extends StatelessWidget {
  const new({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 8, backgroundColor: Color(category.colorValue)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            category.formatTitle(category.name),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The shared field chrome (outline + "Category" label) both the wide
/// dropdown and the narrow wheel-picker trigger sit inside, so the two
/// read as the same kind of control regardless of width.
const _fieldDecoration = InputDecoration(
  labelText: 'Category',
  border: OutlineInputBorder(),
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
);

/// Lets the user assign a category to whatever's being edited (a
/// schedule block, a task): a standard [DropdownButtonFormField] on a
/// wide width, or — since a dropdown menu is awkward to operate with a
/// finger — the same field chrome wrapping a tappable row that opens a
/// [CupertinoPicker] wheel on a narrow one. Either way every row is a
/// [_CategoryRow], and picking one calls [onSelected] immediately, no
/// separate confirm step.
class BlockCategoryPicker extends ConsumerWidget {
  /// Creates a [BlockCategoryPicker].
  const new({
    required this.selectedCategoryId,
    required this.onSelected,
    super.key,
  });

  /// The id of the category currently assigned to the thing being edited.
  final String selectedCategoryId;

  /// Called with a category's id when a new one is picked.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryListProvider).value ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();
    final selected = categoryById(categories, selectedCategoryId);

    if (isNarrow(context)) {
      return InputDecorator(
        decoration: _fieldDecoration,
        child: GestureDetector(
          onTap: () => _showWheelPicker(context, categories, selected.id),
          child: _CategoryRow(category: selected),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      // Forces the field to reset to [selected.id] whenever it changes
      // for a reason other than this field's own [onChanged] — e.g. the
      // item being edited changes underneath it — since a FormField
      // otherwise only reads [initialValue] on its very first build.
      key: ValueKey(selected.id),
      initialValue: selected.id,
      decoration: _fieldDecoration,
      selectedItemBuilder: (context) => [
        for (final category in categories) _CategoryRow(category: category),
      ],
      items: [
        for (final category in categories)
          DropdownMenuItem(
            value: category.id,
            child: _CategoryRow(category: category),
          ),
      ],
      onChanged: (id) {
        if (id != null) onSelected(id);
      },
    );
  }

  /// Opens a bottom sheet containing a [CupertinoPicker] wheel of every
  /// category, initially centered on [selectedId]. Applies [onSelected]
  /// on every settle — there's no separate Done/confirm action.
  Future<void> _showWheelPicker(
    BuildContext context,
    List<Category> categories,
    String selectedId,
  ) {
    final initialItem = categories.indexWhere((c) => c.id == selectedId);
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 216,
          child: CupertinoPicker(
            itemExtent: 48,
            scrollController: FixedExtentScrollController(
              initialItem: initialItem < 0 ? 0 : initialItem,
            ),
            onSelectedItemChanged: (index) => onSelected(categories[index].id),
            children: [
              for (final category in categories)
                Center(child: _CategoryRow(category: category)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Remove the relocated code from `block_edit_modal.dart` and import it instead**

In `lib/features/day/widgets/block_edit_modal.dart`:
- Delete the `_CategoryRow` class, the `_fieldDecoration` constant, and the `BlockCategoryPicker` class (the block identified in Step 1).
- Add `import 'package:taskframe/features/category/widgets/category_picker.dart';`.
- Remove the `import 'package:flutter/cupertino.dart';` line — `CupertinoPicker` was only used by the now-removed `BlockCategoryPicker._showWheelPicker`. The file's other wheel (`_TimeWheelPicker`) uses `ListWheelScrollView`/`FixedExtentScrollController`, which come from `flutter/material.dart` (already imported), not Cupertino. Confirm with `grep -n Cupertino lib/features/day/widgets/block_edit_modal.dart` after deleting — it should return nothing.

- [ ] **Step 4: Move the picker's tests into their own file**

Create `test/widget/category_picker_test.dart` containing the `group('BlockCategoryPicker', ...)` block copied verbatim from `test/widget/block_edit_modal_test.dart` (lines 106–263 as read during exploration), plus its own local copies of the `_pumpPicker` and `_useNarrowView` helpers it needs:

```dart
// test/widget/category_picker_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_picker.dart';

Future<void> _pumpPicker(
  WidgetTester tester,
  ProviderContainer container, {
  required String selectedCategoryId,
  required ValueChanged<String> onSelected,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: BlockCategoryPicker(
          selectedCategoryId: selectedCategoryId,
          onSelected: onSelected,
        ),
      ),
    ),
  ),
);

void _useNarrowView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('BlockCategoryPicker', () {
    group('on a wide width', () {
      testWidgets('shows a labeled dropdown field listing every loaded '
          'category', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: Category.defaultId,
          onSelected: (_) {},
        );
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        expect(find.text('Category'), findsOneWidget);

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        expect(find.text('💼 Work'), findsWidgets);
      });

      testWidgets('selecting an item in the dropdown calls onSelected with '
          'its category id', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        final work = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        String? selected;
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: Category.defaultId,
          onSelected: (id) => selected = id,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Work').last);
        await tester.pumpAndSettle();

        expect(selected, work.id);
      });

      testWidgets('the closed field shows a swatch of the selected '
          "category's color, not a full-color background", (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        final work = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: work.id,
          onSelected: (_) {},
        );
        await tester.pumpAndSettle();

        final swatch = tester.widget<CircleAvatar>(
          find
              .descendant(
                of: find.byType(DropdownButtonFormField<String>),
                matching: find.byType(CircleAvatar),
              )
              .first,
        );
        expect(swatch.backgroundColor, const Color(0xFF2196F3));
      });
    });

    group('on a narrow width', () {
      testWidgets('shows a labeled field with the selected category '
          'instead of a dropdown', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        final work = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
        _useNarrowView(tester);
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: work.id,
          onSelected: (_) {},
        );
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text('Category'), findsOneWidget);
        expect(find.text('💼 Work'), findsOneWidget);
      });

      testWidgets('tapping the chip opens a wheel picker listing every '
          'category', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        _useNarrowView(tester);
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: Category.defaultId,
          onSelected: (_) {},
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Default'));
        await tester.pumpAndSettle();

        expect(find.byType(CupertinoPicker), findsOneWidget);
        expect(find.text('Work'), findsOneWidget);
      });

      testWidgets('settling the wheel on a new category calls onSelected '
          'with its id, with no separate confirm step', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        final work = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        String? selected;
        _useNarrowView(tester);
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: Category.defaultId,
          onSelected: (id) => selected = id,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Default'));
        await tester.pumpAndSettle();
        // Default is the wheel's first (index 0) entry, Work its second;
        // dragging up by one 48px item settles the wheel on Work.
        await tester.drag(find.byType(CupertinoPicker), const Offset(0, -48));
        await tester.pumpAndSettle();

        expect(selected, work.id);
        // No Done/confirm button anywhere in the sheet.
        expect(find.byType(TextButton), findsNothing);
      });
    });
  });
}
```

- [ ] **Step 5: Remove the moved group from `block_edit_modal_test.dart`**

Delete the entire `group('BlockCategoryPicker', ...)` block (originally lines 106–263) from `test/widget/block_edit_modal_test.dart`, along with its now-unused `_pumpPicker`/`_useNarrowView` helpers **only if** nothing later in that file still calls them — check the `BlockEditModal` group (it opens the modal via `_pumpOpenButton`, not `_pumpPicker`, so `_pumpPicker` should be safe to delete; `_useNarrowView` is likely reused by the modal's own narrow-width tests — keep it if so). Update the `import 'package:taskframe/features/day/widgets/block_edit_modal.dart';` import list if `BlockCategoryPicker` was imported explicitly elsewhere in that file (it wasn't — it's the same file that declared it, now re-exported implicitly via the modal's own import of the new location, but the test file itself will need `import 'package:taskframe/features/category/widgets/category_picker.dart';` added if line 983's `expect(find.byType(BlockCategoryPicker), findsOneWidget);` still references it directly).

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: PASS — every existing test (including `day_screen_test.dart`, `block_edit_modal_test.dart`'s remaining groups, and the new `category_picker_test.dart`) still passes, confirming the relocation changed no behavior.

- [ ] **Step 7: Commit**

```bash
git add lib/features/category/widgets/category_picker.dart lib/features/day/widgets/block_edit_modal.dart test/widget/category_picker_test.dart test/widget/block_edit_modal_test.dart
git commit -m "Move BlockCategoryPicker into the category feature"
```

---

### Task 6: `TaskCard`

**Files:**
- Create: `lib/features/task/widgets/task_card.dart`
- Test: `test/widget/task_card_test.dart`

**Interfaces:**
- Consumes: `Task` (Task 1), `Category`/`categoryListProvider`/`categoryById` (existing `category` feature).
- Produces: `class TaskCard extends ConsumerWidget` — `TaskCard({required Task task, required VoidCallback onTap, super.key})`. Reads `categoryListProvider` itself (mirrors how `CategoriesScreen`'s list rows read category color directly; `TaskCard` similarly resolves its own category from `task.categoryId`).

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/task_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/task_card.dart';

Future<ProviderContainer> _seededContainer() async {
  final container = ProviderContainer();
  await container.read(categoryListProvider.future);
  await container.read(taskListProvider.future);
  return container;
}

Future<void> _pumpCard(
  WidgetTester tester,
  ProviderContainer container,
  Task task, {
  VoidCallback? onTap,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: TaskCard(task: task, onTap: onTap ?? () {})),
    ),
  ),
);

void main() {
  group('TaskCard', () {
    testWidgets('shows the task title', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');

      await _pumpCard(tester, container, task);

      expect(find.text('Buy milk'), findsOneWidget);
    });

    testWidgets('prefixes the title with the category emoji when it has one', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final category = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Ship it', categoryId: category.id);

      await _pumpCard(tester, container, task);

      expect(find.text('💼 Ship it'), findsOneWidget);
    });

    testWidgets('uses the category color as its background', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final category = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3);
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Ship it', categoryId: category.id);

      await _pumpCard(tester, container, task);

      final container2 = tester.widget<Container>(
        find.ancestor(
          of: find.text('Ship it'),
          matching: find.byType(Container),
        ),
      );
      final decoration = container2.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF2196F3));
    });

    testWidgets('shows a checked checkbox for a closed task', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      final closed = await container
          .read(taskListProvider.notifier)
          .updateTask(task, closed: true)
          .then((_) => task.copyWith(closed: true));

      await _pumpCard(tester, container, closed);

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isTrue);
    });

    testWidgets('tapping the checkbox toggles closed via the provider', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');

      await _pumpCard(tester, container, task);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.single.closed, isTrue);
    });

    testWidgets('tapping the card body (not the checkbox) calls onTap', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final task = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      var tapped = false;

      await _pumpCard(tester, container, task, onTap: () => tapped = true);
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/task_card_test.dart`
Expected: FAIL — `lib/features/task/widgets/task_card.dart` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/task/widgets/task_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';

/// Renders a single [Task] in the tasks list: a filled card using its
/// category's color (falling back to the theme's own color while
/// categories are still loading, matching `BlockView`'s fallback) and the
/// category's emoji prefixed onto the title, with a leading checkbox that
/// toggles [Task.closed] directly — no need to open the edit modal just
/// to close a task. Closed tasks show their title struck through and
/// dimmed. Tapping the rest of the card calls [onTap]. Uses a plain
/// [Container]/[BoxDecoration] rather than [Card] so its background is
/// the category color itself, matching `BlockView`'s own approach.
class TaskCard extends ConsumerWidget {
  /// Creates a [TaskCard] for [task].
  const new({required this.task, required this.onTap, super.key});

  /// The task to render.
  final Task task;

  /// Called when the card body (outside the checkbox) is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final categories = ref.watch(categoryListProvider).value ?? const [];
    final category = categories.isEmpty
        ? null
        : categoryById(categories, task.categoryId);
    final categoryColor = category == null ? null : Color(category.colorValue);
    final title = category?.formatTitle(task.title) ?? task.title;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: categoryColor ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Checkbox(
          value: task.closed,
          onChanged: (value) => ref
              .read(taskListProvider.notifier)
              .updateTask(task, closed: value ?? !task.closed),
        ),
        title: Text(
          title,
          style: TextStyle(
            decoration: task.closed ? TextDecoration.lineThrough : null,
            color: task.closed ? Theme.of(context).disabledColor : null,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/task_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/task/widgets/task_card.dart test/widget/task_card_test.dart
git commit -m "Add TaskCard"
```

---

### Task 7: `TaskEditModal`

**Files:**
- Create: `lib/features/task/widgets/task_edit_modal.dart`
- Test: `test/widget/task_edit_modal_test.dart`

**Interfaces:**
- Consumes: `Task` (Task 1), `taskListProvider` (Task 4), `BlockCategoryPicker` (Task 5, now in `category` feature).
- Produces: `Future<void> showTaskEditModal({required BuildContext context, Task? task})` — `task == null` is create mode, matching `showCategoryEditSheet`'s create/edit convention.

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/task_edit_modal_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/task_edit_modal.dart';

Future<ProviderContainer> _seededContainer() async {
  final container = ProviderContainer();
  await container.read(categoryListProvider.future);
  await container.read(taskListProvider.future);
  return container;
}

Future<void> _pumpOpenButton(
  WidgetTester tester,
  ProviderContainer container, {
  Task? task,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showTaskEditModal(context: context, task: task),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('TaskEditModal', () {
    testWidgets('create mode: entering a title and saving adds a task', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.where((t) => t.title == 'Buy milk'), hasLength(1));
    });

    testWidgets('create mode: Save is disabled while the title is empty', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('create mode: shows no Delete action', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('edit mode: pre-fills the title field', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pumpOpenButton(tester, container, task: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Buy milk'), findsOneWidget);
    });

    testWidgets('edit mode: changing the title and saving persists it', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pumpOpenButton(tester, container, task: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Buy oat milk');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.singleWhere((t) => t.id == created.id).title, 'Buy oat milk');
    });

    testWidgets('edit mode: toggling the Closed switch and saving persists it', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pumpOpenButton(tester, container, task: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.singleWhere((t) => t.id == created.id).closed, isTrue);
    });

    testWidgets('edit mode: Delete asks for confirmation, then removes the '
        'task', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pumpOpenButton(tester, container, task: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.where((t) => t.id == created.id), isEmpty);
    });

    testWidgets('Cancel dismisses the modal without saving changes', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final tasks = container.read(taskListProvider).value!;
      expect(tasks.where((t) => t.title == 'Buy milk'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/task_edit_modal_test.dart`
Expected: FAIL — `lib/features/task/widgets/task_edit_modal.dart` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/task/widgets/task_edit_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/widgets/category_picker.dart';
import 'package:taskframe/features/task/models/task.dart';
import 'package:taskframe/features/task/providers.dart';

/// Opens the edit modal for [task] (edit mode) or, when [task] is `null`,
/// for creating a new task (create mode). Near-fullscreen on a narrow
/// (mobile) width, a centered fixed-width dialog on a wide one — matching
/// `showCategoryEditSheet`'s responsive shell.
Future<void> showTaskEditModal({required BuildContext context, Task? task}) {
  if (isNarrow(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TaskEditModalContent(task: task),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: _TaskEditModalContent(task: task),
      ),
    ),
  );
}

class _TaskEditModalContent extends ConsumerStatefulWidget {
  const new({this.task});

  final Task? task;

  @override
  ConsumerState<_TaskEditModalContent> createState() =>
      _TaskEditModalContentState();
}

class _TaskEditModalContentState extends ConsumerState<_TaskEditModalContent> {
  late final TextEditingController _titleController;
  late String _categoryId;
  late bool _closed;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _categoryId = widget.task?.categoryId ?? Category.defaultId;
    _closed = widget.task?.closed ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final notifier = ref.read(taskListProvider.notifier);
    if (widget.task == null) {
      await notifier.addTask(
        title: _titleController.text,
        categoryId: _categoryId,
      );
    } else {
      await notifier.updateTask(
        widget.task!,
        title: _titleController.text,
        closed: _closed,
        categoryId: _categoryId,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed ?? false) {
      await ref.read(taskListProvider.notifier).deleteTask(widget.task!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            BlockCategoryPicker(
              selectedCategoryId: _categoryId,
              onSelected: (id) => setState(() => _categoryId = id),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Closed'),
              value: _closed,
              onChanged: (value) => setState(() => _closed = value),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.task != null)
                  TextButton(
                    onPressed: _confirmDelete,
                    child: const Text('Delete'),
                  )
                else
                  const SizedBox(),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: _titleController.text.isNotEmpty
                          ? _save
                          : null,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/task_edit_modal_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/task/widgets/task_edit_modal.dart test/widget/task_edit_modal_test.dart
git commit -m "Add TaskEditModal"
```

---

### Task 8: `TasksScreen`

**Files:**
- Create: `lib/features/task/widgets/tasks_screen.dart`
- Test: `test/widget/tasks_screen_test.dart`

**Interfaces:**
- Consumes: `taskListProvider` (Task 4), `TaskCard` (Task 6), `showTaskEditModal` (Task 7).
- Produces: `class TasksScreen extends ConsumerWidget`.

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/tasks_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/tasks_screen.dart';

Future<void> _pump(WidgetTester tester, {ProviderContainer? container}) async {
  if (container != null) {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TasksScreen()),
      ),
    );
  } else {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TasksScreen())),
    );
  }
  await tester.pump();
}

void main() {
  group('TasksScreen', () {
    testWidgets('starts empty', (tester) async {
      await _pump(tester);

      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('the add-task action has an accessible tooltip', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byTooltip('Add task'), findsOneWidget);
    });

    testWidgets(
      'adding a task via the app bar action shows it in the list',
      (tester) async {
        await _pump(tester);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Buy milk');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(find.text('Buy milk'), findsOneWidget);
      },
    );

    testWidgets('tapping a task card opens it in edit mode', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pump(tester, container: container);

      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Buy oat milk');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Buy oat milk'), findsOneWidget);
      expect(find.text('Buy milk'), findsNothing);
    });

    testWidgets('toggling a card checkbox closes the task without opening '
        'the modal', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container.read(taskListProvider.future);
      await container
          .read(taskListProvider.notifier)
          .addTask(title: 'Buy milk');
      await _pump(tester, container: container);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      final tasks = container.read(taskListProvider).value!;
      expect(tasks.single.closed, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/tasks_screen_test.dart`
Expected: FAIL — `lib/features/task/widgets/tasks_screen.dart` doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/task/widgets/tasks_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/task/widgets/task_card.dart';
import 'package:taskframe/features/task/widgets/task_edit_modal.dart';

/// Lists every task as a [TaskCard], in creation order, and lets the user
/// add or edit one via [showTaskEditModal]. Closing a task is a checkbox
/// on its own card — see [TaskCard] — so this screen only wires up
/// add/open-for-edit.
class TasksScreen extends ConsumerWidget {
  /// Creates a [TasksScreen].
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(taskListProvider);

    return Scaffold(
      appBar: AppBar(
        // Reserves the leading slot so AppShell's floating hamburger button
        // (narrow widths only) has room without covering the title.
        leading: const SizedBox(),
        title: const Text('Tasks'),
        actions: [
          IconButton(
            tooltip: 'Add task',
            icon: const Icon(Icons.add),
            onPressed: () => showTaskEditModal(context: context),
          ),
        ],
      ),
      body: switch (tasksAsync) {
        AsyncData(:final value) => LayoutBuilder(
          builder: (context, constraints) {
            final isNarrowWidth = constraints.maxWidth < narrowBreakpoint;
            final list = ListView(
              padding: isNarrowWidth
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final task in value)
                  TaskCard(
                    task: task,
                    onTap: () => showTaskEditModal(context: context, task: task),
                  ),
              ],
            );
            if (isNarrowWidth) return list;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: list,
              ),
            );
          },
        ),
        AsyncError() => const Center(child: Text('Failed to load tasks')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/tasks_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/task/widgets/tasks_screen.dart test/widget/tasks_screen_test.dart
git commit -m "Add TasksScreen"
```

---

### Task 9: Wire up routing, nav, and sembast persistence

**Files:**
- Modify: `lib/router.dart`
- Modify: `lib/core/widgets/app_shell.dart`
- Modify: `lib/core/storage/sembast_overrides.dart`
- Modify: `test/widget/router_test.dart`

**Interfaces:**
- Consumes: `TasksScreen` (Task 8), `taskRepositoryProvider` (Task 4), `SembastTaskRepository` (Task 3).

- [ ] **Step 1: Write the failing test**

Add to `test/widget/router_test.dart`, inside the existing `group('appRouter', ...)`:

```dart
    testWidgets('tapping Tasks navigates to /tasks', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
      );
      await tester.pump();

      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();

      expect(find.text('Tasks'), findsWidgets);
      final shell = tester.widget<AppShell>(find.byType(AppShell));
      expect(shell.navigationShell.currentIndex, 3);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/router_test.dart`
Expected: FAIL — no "Tasks" destination exists yet, so `find.text('Tasks')` finds nothing to tap.

- [ ] **Step 3: Write minimal implementation**

In `lib/router.dart`, add the import and a fourth branch:

```dart
import 'package:taskframe/features/task/widgets/tasks_screen.dart';
```

```dart
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/tasks', builder: (context, state) => const TasksScreen()),
          ],
        ),
```

(appended after the `/categories` branch, as the fourth entry in `branches`).

In `lib/core/widgets/app_shell.dart`, add a fourth entry to `_destinations`, appended last:

```dart
  _Destination(icon: Icons.check_circle_outline, label: 'Tasks'),
```

In `lib/core/storage/sembast_overrides.dart`, add the task repository override:

```dart
import 'package:taskframe/features/task/data/sembast_task_repository.dart';
import 'package:taskframe/features/task/providers.dart';
```

```dart
  taskRepositoryProvider.overrideWithValue(SembastTaskRepository(db)),
```

(added to the `sembastOverrides` list alongside the other four).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/router_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: PASS — confirms the new branch/destination doesn't regress `app_shell_test.dart` (which uses its own fixed 3-branch test router, unaffected) or any other nav-adjacent test.

- [ ] **Step 6: Commit**

```bash
git add lib/router.dart lib/core/widgets/app_shell.dart lib/core/storage/sembast_overrides.dart test/widget/router_test.dart
git commit -m "Wire up the Tasks nav destination and sembast persistence"
```

---

## Final check

- [ ] Run `flutter test` once more from a clean state and confirm every test in the suite passes.
- [ ] Run `flutter analyze` and confirm no new warnings/errors were introduced.
