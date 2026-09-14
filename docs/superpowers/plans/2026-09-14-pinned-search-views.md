# Pinned Search Views Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user pin a Tasks search query via a star icon in the search bar; pinned queries persist as named "saved views" listed in the sidebar under Tasks, where they can be renamed, deleted, and drag-reordered, and clicking one reloads that query into the search bar.

**Architecture:** A new `lib/features/saved_search/` feature module (model + repository + Riverpod provider), following the exact shape of `lib/features/category/`. `tasks_screen.dart` gets a star `IconButton` next to the existing filter icon, plus a route-sync fix so external navigation into an already-mounted Tasks screen updates the search field. `app_shell.dart` gets a new "Saved views" section appended to the existing `NavigationDrawer` children (both narrow and wide), built from a `ReorderableListView`.

**Tech Stack:** Flutter 3.13 (Dart `^3.13.2`, primary-constructor `new(...)` syntax), `flutter_riverpod` (`AsyncNotifier`/`Provider`), `go_router` (`^18.0.1`), `sembast`/`sembast_web` for persistence, `uuid` for id generation. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-14-pinned-search-views-design.md`

## Global Constraints

- Follow the codebase's `new(...)` primary-constructor syntax for every class constructor (as used throughout, e.g. `Category`, `SembastCategoryRepository`).
- Every new repository must be added to `lib/core/storage/sembast_overrides.dart` and to `test/unit/sembast_overrides_test.dart` — that list is deliberately kept exhaustive so a forgotten repository doesn't silently ship without persistence.
- No confirmation dialog on delete (spec: "Out of scope").
- No dedupe of saved views with identical query text (spec: "Out of scope").
- Default view name is `Tasks view ${existingCount + 1}` — count-based, not an ever-increasing counter (spec-approved; number reuse after deletion is fine).

---

### Task 1: `SavedSearch` model, store, and in-memory repository

**Files:**
- Create: `lib/features/saved_search/models/saved_search.dart`
- Create: `lib/features/saved_search/data/saved_search_repository.dart`
- Modify: `lib/core/storage/app_database.dart`
- Test: `test/unit/saved_search_test.dart`
- Test: `test/unit/saved_search_repository_test.dart`

**Interfaces:**
- Produces: `SavedSearch({required String id, required String name, required String query, required int order})`, `SavedSearch.fromMap(Map<String, Object?>)`, `SavedSearch.toMap()`, `SavedSearch.copyWith({String? name, String? query, int? order})`.
- Produces: `abstract class SavedSearchRepository { Future<List<SavedSearch>> load(); Future<SavedSearch> add({required String name, required String query}); Future<SavedSearch> rename(SavedSearch view, String name); Future<void> delete(SavedSearch view); Future<void> reorder(List<SavedSearch> orderedViews); }` and `InMemorySavedSearchRepository implements SavedSearchRepository`.
- Produces: `final StoreRef<String, Map<String, Object?>> savedSearchesStore` in `app_database.dart`.

- [ ] **Step 1: Write the failing model test**

```dart
// test/unit/saved_search_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/saved_search/models/saved_search.dart';

void main() {
  group('SavedSearch', () {
    const view = SavedSearch(
      id: 'view-1',
      name: 'Tasks view 1',
      query: '#urgent /work',
      order: 0,
    );

    test('round-trips through toMap/fromMap', () {
      expect(SavedSearch.fromMap(view.toMap()), view);
    });

    test('copyWith replaces only the given fields', () {
      final renamed = view.copyWith(name: 'Urgent work');

      expect(renamed.name, 'Urgent work');
      expect(renamed.query, view.query);
      expect(renamed.order, view.order);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/saved_search_test.dart`
Expected: FAIL — `saved_search.dart` doesn't exist yet.

- [ ] **Step 3: Implement the model**

```dart
// lib/features/saved_search/models/saved_search.dart

/// A pinned Tasks search query, shown in the sidebar under "Tasks".
class SavedSearch {
  /// Creates a [SavedSearch].
  const new({
    required this.id,
    required this.name,
    required this.query,
    required this.order,
  });

  /// Reconstructs a [SavedSearch] from a map produced by [toMap].
  factory fromMap(Map<String, Object?> map) => SavedSearch(
    id: map['id']! as String,
    name: map['name']! as String,
    query: map['query']! as String,
    order: map['order']! as int,
  );

  /// Unique identifier for this saved view.
  final String id;

  /// User-editable display name, e.g. "Tasks view 2".
  final String name;

  /// The raw search text this view reloads into the Tasks search bar.
  final String query;

  /// Sidebar position — lower sorts first.
  final int order;

  /// Returns a copy of this view with any of [name]/[query]/[order]
  /// replaced.
  SavedSearch copyWith({String? name, String? query, int? order}) =>
      SavedSearch(
        id: id,
        name: name ?? this.name,
        query: query ?? this.query,
        order: order ?? this.order,
      );

  /// This view's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'query': query,
    'order': order,
  };

  @override
  bool operator ==(Object other) =>
      other is SavedSearch &&
      other.id == id &&
      other.name == name &&
      other.query == query &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, name, query, order);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/saved_search_test.dart`
Expected: PASS

- [ ] **Step 5: Add the sembast store**

In `lib/core/storage/app_database.dart`, add below the existing `settingsStore` declaration:

```dart
/// Saved (pinned) Tasks search views, keyed by view id, each record
/// carrying an `order` field for sidebar position.
final StoreRef<String, Map<String, Object?>> savedSearchesStore =
    stringMapStoreFactory.store('saved_searches');
```

- [ ] **Step 6: Write the failing in-memory repository test**

```dart
// test/unit/saved_search_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/saved_search/data/saved_search_repository.dart';

void main() {
  group('InMemorySavedSearchRepository', () {
    test('load starts empty', () async {
      final repository = InMemorySavedSearchRepository();

      expect(await repository.load(), isEmpty);
    });

    test('add appends a new view with the next order', () async {
      final repository = InMemorySavedSearchRepository();

      await repository.add(name: 'Tasks view 1', query: '#urgent');
      final second = await repository.add(
        name: 'Tasks view 2',
        query: '@work',
      );

      final views = await repository.load();
      expect(views, hasLength(2));
      expect(second.order, 1);
    });

    test('two added views get distinct ids', () async {
      final repository = InMemorySavedSearchRepository();

      final first = await repository.add(name: 'A', query: 'a');
      final second = await repository.add(name: 'B', query: 'b');

      expect(first.id, isNot(second.id));
    });

    test('rename updates the name and persists it', () async {
      final repository = InMemorySavedSearchRepository();
      final added = await repository.add(name: 'Tasks view 1', query: '#a');

      final renamed = await repository.rename(added, 'Urgent');

      expect(renamed.name, 'Urgent');
      final views = await repository.load();
      expect(views.single.name, 'Urgent');
    });

    test('delete removes the view', () async {
      final repository = InMemorySavedSearchRepository();
      final added = await repository.add(name: 'Tasks view 1', query: '#a');

      await repository.delete(added);

      expect(await repository.load(), isEmpty);
    });

    test('reorder persists the given order and reassigns order fields', () async {
      final repository = InMemorySavedSearchRepository();
      final first = await repository.add(name: 'First', query: 'a');
      final second = await repository.add(name: 'Second', query: 'b');

      await repository.reorder([second, first]);

      final views = await repository.load();
      expect(views.map((v) => v.name), ['Second', 'First']);
      expect(views.map((v) => v.order), [0, 1]);
    });
  });
}
```

- [ ] **Step 7: Run test to verify it fails**

Run: `flutter test test/unit/saved_search_repository_test.dart`
Expected: FAIL — `saved_search_repository.dart` doesn't exist yet.

- [ ] **Step 8: Implement the repository interface and in-memory implementation**

```dart
// lib/features/saved_search/data/saved_search_repository.dart
import 'package:taskframe/features/saved_search/models/saved_search.dart';

/// Loads and stores pinned Tasks search views.
///
/// Implementations back this with whatever storage is appropriate (in
/// memory today, sembast later); callers depend only on this interface.
abstract class SavedSearchRepository {
  /// Returns all saved views, ordered by [SavedSearch.order].
  Future<List<SavedSearch>> load();

  /// Creates a new saved view and returns it.
  Future<SavedSearch> add({required String name, required String query});

  /// Renames [view] to [name], leaving its query unchanged. Returns the
  /// updated view.
  Future<SavedSearch> rename(SavedSearch view, String name);

  /// Removes [view].
  Future<void> delete(SavedSearch view);

  /// Persists [orderedViews] as the new sidebar order — index 0 becomes
  /// `order: 0`, and so on.
  Future<void> reorder(List<SavedSearch> orderedViews);
}

/// A [SavedSearchRepository] that keeps saved views in memory for the
/// life of the app.
class InMemorySavedSearchRepository implements SavedSearchRepository {
  final List<SavedSearch> _views = [];
  int _nextId = 1;

  @override
  Future<List<SavedSearch>> load() async => List.unmodifiable(_views);

  @override
  Future<SavedSearch> add({
    required String name,
    required String query,
  }) async {
    final view = SavedSearch(
      id: 'saved-search-${_nextId++}',
      name: name,
      query: query,
      order: _views.length,
    );
    _views.add(view);
    return view;
  }

  @override
  Future<SavedSearch> rename(SavedSearch view, String name) async {
    final index = _views.indexWhere((v) => v.id == view.id);
    final updated = _views[index].copyWith(name: name);
    _views[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(SavedSearch view) async {
    _views.removeWhere((v) => v.id == view.id);
  }

  @override
  Future<void> reorder(List<SavedSearch> orderedViews) async {
    _views
      ..clear()
      ..addAll([
        for (var i = 0; i < orderedViews.length; i++)
          orderedViews[i].copyWith(order: i),
      ]);
  }
}
```

- [ ] **Step 9: Run test to verify it passes**

Run: `flutter test test/unit/saved_search_repository_test.dart test/unit/saved_search_test.dart`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add lib/features/saved_search/models/saved_search.dart \
        lib/features/saved_search/data/saved_search_repository.dart \
        lib/core/storage/app_database.dart \
        test/unit/saved_search_test.dart \
        test/unit/saved_search_repository_test.dart
git commit -m "feat: add SavedSearch model and in-memory repository"
```

---

### Task 2: Sembast-backed repository, wired into persistence

**Files:**
- Create: `lib/features/saved_search/data/sembast_saved_search_repository.dart`
- Modify: `lib/core/storage/sembast_overrides.dart`
- Test: `test/unit/sembast_saved_search_repository_test.dart`
- Test: `test/unit/sembast_overrides_test.dart` (extend)

**Interfaces:**
- Consumes: `SavedSearchRepository`, `SavedSearch` (Task 1); `savedSearchesStore` (Task 1); `savedSearchRepositoryProvider` (Task 3 — this task's `sembast_overrides.dart` edit references it, so do Task 3 first if working strictly in order, or leave this override addition as the last step of Task 3 instead; the step below assumes `savedSearchRepositoryProvider` already exists from Task 3).
- Produces: `SembastSavedSearchRepository implements SavedSearchRepository`.

**Note on ordering:** this task's sembast repository class has no dependency on Task 3, but wiring it into `sembast_overrides.dart` does (it references `savedSearchRepositoryProvider`). Do Steps 1–4 (the repository itself) now; do Steps 5–7 (wiring) only after Task 3 is complete. If executing tasks strictly in order, skip Steps 5–7 here and do them as the final steps of Task 3 instead — either ordering is fine as long as both land before Task 4.

- [ ] **Step 1: Write the failing sembast repository test**

```dart
// test/unit/sembast_saved_search_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/features/saved_search/data/sembast_saved_search_repository.dart';

void main() {
  group('SembastSavedSearchRepository', () {
    late SembastSavedSearchRepository repository;

    setUp(() async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastSavedSearchRepository(db);
    });

    test('load starts empty', () async {
      expect(await repository.load(), isEmpty);
    });

    test('add appends a new view with the next order', () async {
      await repository.add(name: 'Tasks view 1', query: '#urgent');
      final second = await repository.add(name: 'Tasks view 2', query: '@work');

      final views = await repository.load();
      expect(views, hasLength(2));
      expect(second.order, 1);
    });

    test('added views load back in creation order', () async {
      await repository.add(name: 'First', query: 'a');
      await repository.add(name: 'Second', query: 'b');

      final views = await repository.load();

      expect(views[0].name, 'First');
      expect(views[1].name, 'Second');
    });

    test('rename replaces the view in a later load', () async {
      final added = await repository.add(name: 'Tasks view 1', query: '#a');

      await repository.rename(added, 'Urgent');

      final views = await repository.load();
      expect(views.single.name, 'Urgent');
    });

    test('delete removes the view from a later load', () async {
      final added = await repository.add(name: 'Tasks view 1', query: '#a');

      await repository.delete(added);

      expect(await repository.load(), isEmpty);
    });

    test('reorder persists the given order', () async {
      final first = await repository.add(name: 'First', query: 'a');
      final second = await repository.add(name: 'Second', query: 'b');

      await repository.reorder([second, first]);

      final views = await repository.load();
      expect(views.map((v) => v.name), ['Second', 'First']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/sembast_saved_search_repository_test.dart`
Expected: FAIL — `sembast_saved_search_repository.dart` doesn't exist yet.

- [ ] **Step 3: Implement the sembast repository**

```dart
// lib/features/saved_search/data/sembast_saved_search_repository.dart
import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/saved_search/data/saved_search_repository.dart';
import 'package:taskframe/features/saved_search/models/saved_search.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A [SavedSearchRepository] backed by a sembast [Database], persisting
/// saved views across restarts. Records are keyed by [SavedSearch.id].
class SembastSavedSearchRepository implements SavedSearchRepository {
  /// Creates a [SembastSavedSearchRepository] reading/writing [_db].
  new(this._db);

  final Database _db;

  @override
  Future<List<SavedSearch>> load() async {
    final finder = Finder(sortOrders: [SortOrder('order')]);
    final records = await savedSearchesStore.find(_db, finder: finder);
    return [for (final record in records) SavedSearch.fromMap(record.value)];
  }

  @override
  Future<SavedSearch> add({
    required String name,
    required String query,
  }) async {
    final existing = await load();
    final view = SavedSearch(
      id: _uuid.v4(),
      name: name,
      query: query,
      order: existing.length,
    );
    await savedSearchesStore.record(view.id).put(_db, view.toMap());
    return view;
  }

  @override
  Future<SavedSearch> rename(SavedSearch view, String name) async {
    final updated = view.copyWith(name: name);
    await savedSearchesStore.record(updated.id).put(_db, updated.toMap());
    return updated;
  }

  @override
  Future<void> delete(SavedSearch view) async {
    await savedSearchesStore.record(view.id).delete(_db);
  }

  @override
  Future<void> reorder(List<SavedSearch> orderedViews) async {
    for (var i = 0; i < orderedViews.length; i++) {
      final updated = orderedViews[i].copyWith(order: i);
      await savedSearchesStore.record(updated.id).put(_db, updated.toMap());
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/sembast_saved_search_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Wire into `sembastOverrides` (only after Task 3's `savedSearchRepositoryProvider` exists)**

In `lib/core/storage/sembast_overrides.dart`, add the import and one line to the returned list:

```dart
import 'package:taskframe/features/saved_search/data/sembast_saved_search_repository.dart';
import 'package:taskframe/features/saved_search/providers.dart';
```

```dart
  savedSearchRepositoryProvider.overrideWithValue(
    SembastSavedSearchRepository(db),
  ),
```

(Add both the imports, alphabetically among the existing `import` lines, and the override entry, alongside the existing entries in the `sembastOverrides` list.)

- [ ] **Step 6: Extend the overrides test**

In `test/unit/sembast_overrides_test.dart`, add the import:

```dart
import 'package:taskframe/features/saved_search/data/sembast_saved_search_repository.dart';
import 'package:taskframe/features/saved_search/providers.dart';
```

and add inside the `test(...)` body, alongside the existing `expect` calls:

```dart
    expect(
      container.read(savedSearchRepositoryProvider),
      isA<SembastSavedSearchRepository>(),
    );
```

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/unit/sembast_overrides_test.dart`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add lib/features/saved_search/data/sembast_saved_search_repository.dart \
        lib/core/storage/sembast_overrides.dart \
        test/unit/sembast_saved_search_repository_test.dart \
        test/unit/sembast_overrides_test.dart
git commit -m "feat: add sembast-backed saved search repository"
```

---

### Task 3: `SavedSearchListNotifier` provider

**Files:**
- Create: `lib/features/saved_search/providers.dart`
- Test: `test/unit/saved_search_providers_test.dart`

**Interfaces:**
- Consumes: `SavedSearchRepository`, `InMemorySavedSearchRepository`, `SavedSearch` (Task 1).
- Produces: `final savedSearchRepositoryProvider = Provider<SavedSearchRepository>(...)`; `class SavedSearchListNotifier extends AsyncNotifier<List<SavedSearch>>` with `Future<SavedSearch> addView(String query)`, `Future<void> renameView(SavedSearch view, String name)`, `Future<void> deleteView(SavedSearch view)`, `Future<void> reorder(int oldIndex, int newIndex)`; `final savedSearchListProvider = AsyncNotifierProvider<SavedSearchListNotifier, List<SavedSearch>>(...)`.

- [ ] **Step 1: Write the failing provider test**

```dart
// test/unit/saved_search_providers_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/saved_search/providers.dart';

void main() {
  group('savedSearchListProvider', () {
    test('starts empty', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final views = await container.read(savedSearchListProvider.future);

      expect(views, isEmpty);
    });

    test('addView creates "Tasks view 1" for the first view', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(savedSearchListProvider.future);

      final added = await container
          .read(savedSearchListProvider.notifier)
          .addView('#urgent');

      expect(added.name, 'Tasks view 1');
      expect(added.query, '#urgent');
    });

    test('addView numbers the second view "Tasks view 2"', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(savedSearchListProvider.future);
      await container.read(savedSearchListProvider.notifier).addView('#a');

      final second = await container
          .read(savedSearchListProvider.notifier)
          .addView('#b');

      expect(second.name, 'Tasks view 2');
    });

    test('renameView updates the name in state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(savedSearchListProvider.future);
      final added = await container
          .read(savedSearchListProvider.notifier)
          .addView('#a');

      await container
          .read(savedSearchListProvider.notifier)
          .renameView(added, 'Urgent');

      final views = container.read(savedSearchListProvider).value!;
      expect(views.single.name, 'Urgent');
    });

    test('deleteView removes the view from state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(savedSearchListProvider.future);
      final added = await container
          .read(savedSearchListProvider.notifier)
          .addView('#a');

      await container
          .read(savedSearchListProvider.notifier)
          .deleteView(added);

      final views = container.read(savedSearchListProvider).value!;
      expect(views, isEmpty);
    });

    test('reorder moves a view to its new index', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(savedSearchListProvider.future);
      await container.read(savedSearchListProvider.notifier).addView('#a');
      await container.read(savedSearchListProvider.notifier).addView('#b');

      await container.read(savedSearchListProvider.notifier).reorder(0, 2);

      final views = container.read(savedSearchListProvider).value!;
      expect(views.map((v) => v.query), ['#b', '#a']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/saved_search_providers_test.dart`
Expected: FAIL — `providers.dart` doesn't exist yet.

- [ ] **Step 3: Implement the providers**

```dart
// lib/features/saved_search/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/saved_search/data/saved_search_repository.dart';
import 'package:taskframe/features/saved_search/models/saved_search.dart';

/// The backing store for saved search views.
///
/// Overriding this single provider (e.g. with a sembast-backed
/// [SavedSearchRepository]) is enough to change where saved views are
/// loaded from and saved to; nothing downstream needs to change.
final savedSearchRepositoryProvider = Provider<SavedSearchRepository>(
  (ref) => InMemorySavedSearchRepository(),
);

/// Holds the list of saved search views, loaded from
/// [savedSearchRepositoryProvider], and lets consumers add/rename/delete/
/// reorder them.
class SavedSearchListNotifier extends AsyncNotifier<List<SavedSearch>> {
  @override
  Future<List<SavedSearch>> build() =>
      ref.watch(savedSearchRepositoryProvider).load();

  /// Creates a new saved view for [query], named "Tasks view N" where N
  /// is the current view count plus one, adds it to state, and returns
  /// it.
  Future<SavedSearch> addView(String query) async {
    final repository = ref.read(savedSearchRepositoryProvider);
    final count = state.value?.length ?? 0;
    final added = await repository.add(
      name: 'Tasks view ${count + 1}',
      query: query,
    );
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Renames [view] to [name], persisting via the repository and
  /// refreshing state.
  Future<void> renameView(SavedSearch view, String name) async {
    final repository = ref.read(savedSearchRepositoryProvider);
    final updated = await repository.rename(view, name);
    state = AsyncData([
      for (final v in state.value ?? <SavedSearch>[])
        if (v.id == view.id) updated else v,
    ]);
  }

  /// Removes [view], persisting via the repository and refreshing state.
  Future<void> deleteView(SavedSearch view) async {
    final repository = ref.read(savedSearchRepositoryProvider);
    await repository.delete(view);
    state = AsyncData([
      for (final v in state.value ?? <SavedSearch>[])
        if (v.id != view.id) v,
    ]);
  }

  /// Moves the view at [oldIndex] to [newIndex] — same index semantics as
  /// [ReorderableListView.onReorder] (i.e. [newIndex] is the index in the
  /// list *before* the moved item is removed) — persisting the new order
  /// via the repository and refreshing state.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final repository = ref.read(savedSearchRepositoryProvider);
    final current = [...?state.value];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = current.removeAt(oldIndex);
    current.insert(newIndex, moved);
    state = AsyncData(current);
    await repository.reorder(current);
  }
}

/// The list of saved search views, in sidebar order.
final savedSearchListProvider =
    AsyncNotifierProvider<SavedSearchListNotifier, List<SavedSearch>>(
      SavedSearchListNotifier.new,
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/saved_search_providers_test.dart`
Expected: PASS

- [ ] **Step 5: Complete Task 2's deferred wiring (Steps 5–7 of Task 2), then verify**

Now that `savedSearchRepositoryProvider` exists, go back and do Task 2's Steps 5–7 (wire `SembastSavedSearchRepository` into `sembast_overrides.dart` and its test) if not already done.

Run: `flutter test test/unit/sembast_overrides_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/saved_search/providers.dart \
        test/unit/saved_search_providers_test.dart \
        lib/core/storage/sembast_overrides.dart \
        test/unit/sembast_overrides_test.dart
git commit -m "feat: add SavedSearchListNotifier for saved view CRUD + reorder"
```

---

### Task 4: Star icon in the Tasks search bar

**Files:**
- Modify: `lib/features/task/widgets/tasks_screen.dart`
- Test: `test/widget/tasks_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `savedSearchListProvider`, `SavedSearchListNotifier.addView`/`deleteView` (Task 3); `SavedSearch` (Task 1).

**Context:** the search field's `suffixIcon` is a `Row` built at `lib/features/task/widgets/tasks_screen.dart` around line 634-654, currently `[clear icon (if text non-empty), filter_alt icon]`. Add the star as a third entry, after `filter_alt`.

- [ ] **Step 1: Write the failing widget test**

`test/widget/tasks_screen_test.dart` already has a `_pump(WidgetTester tester, {ProviderContainer? container})` helper (wraps `TasksScreen` in `ProviderScope`/`UncontrolledProviderScope`) — reuse it exactly as the existing `'tapping a task card opens it in edit mode'` test does (build a `ProviderContainer`, pass it to `_pump`, then read provider state directly off that container). Add:

```dart
  testWidgets('star icon is outlined for a query with no saved view', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '#urgent');
    await tester.pump();

    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('tapping the star icon creates a saved view', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(categoryListProvider.future);
    await container.read(taskListProvider.future);
    await container.read(savedSearchListProvider.future);
    await _pump(tester, container: container);
    await tester.enterText(find.byType(TextField), '#urgent');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pump();

    final views = container.read(savedSearchListProvider).value!;
    expect(views.single.query, '#urgent');
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('tapping a filled star deletes the saved view', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(categoryListProvider.future);
    await container.read(taskListProvider.future);
    await container.read(savedSearchListProvider.future);
    await _pump(tester, container: container);
    await tester.enterText(find.byType(TextField), '#urgent');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.star));
    await tester.pump();

    final views = container.read(savedSearchListProvider).value!;
    expect(views, isEmpty);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
  });

  testWidgets('star icon is hidden when the query is empty', (tester) async {
    await _pump(tester);

    expect(find.byIcon(Icons.star_border), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
  });
```

Add the import this needs at the top of the file, alongside the existing `taskframe` imports:

```dart
import 'package:taskframe/features/saved_search/providers.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/tasks_screen_test.dart`
Expected: FAIL — no star icon exists yet.

- [ ] **Step 3: Implement the star icon**

In `lib/features/task/widgets/tasks_screen.dart`, add the import:

```dart
import 'package:taskframe/features/saved_search/models/saved_search.dart';
import 'package:taskframe/features/saved_search/providers.dart';
```

In `build()`, before the `return Scaffold(...)`, add:

```dart
    final savedViews = ref.watch(savedSearchListProvider).value ?? const <SavedSearch>[];
    final currentQuery = _searchController.text.trim();
    SavedSearch? matchingView;
    for (final view in savedViews) {
      if (view.query == currentQuery) {
        matchingView = view;
        break;
      }
    }
```

In the `suffixIcon: Row(... children: [...])` list, after the existing `filter_alt` `IconButton` and before the closing `],`, add:

```dart
                              if (currentQuery.isNotEmpty)
                                IconButton(
                                  icon: Icon(
                                    matchingView != null
                                        ? Icons.star
                                        : Icons.star_border,
                                  ),
                                  tooltip: matchingView != null
                                      ? 'Remove pinned view'
                                      : 'Pin this search',
                                  onPressed: () {
                                    if (matchingView != null) {
                                      ref
                                          .read(savedSearchListProvider.notifier)
                                          .deleteView(matchingView!);
                                    } else {
                                      ref
                                          .read(savedSearchListProvider.notifier)
                                          .addView(currentQuery);
                                    }
                                  },
                                ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/tasks_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `flutter test`
Expected: PASS (all prior tests unaffected)

- [ ] **Step 6: Commit**

```bash
git add lib/features/task/widgets/tasks_screen.dart test/widget/tasks_screen_test.dart
git commit -m "feat: add star icon to pin/unpin the current search"
```

---

### Task 5: Sync the search field to external route changes

**Files:**
- Modify: `lib/features/task/widgets/tasks_screen.dart`
- Test: `test/widget/tasks_screen_test.dart` (extend)

**Why this task exists:** go_router's `StatefulShellRoute.indexedStack` keeps `TasksScreen` mounted across branch switches. Today `_searchController` is only seeded from the URL once, in `initState` (line ~173). Saved views (Task 7) will navigate to `/tasks?q=...` via `context.go` while `TasksScreen` may already be mounted — without this fix, `initState` won't re-run and the search field won't update to show the loaded view's query.

**Interfaces:**
- No new public interfaces; this only changes `_TasksScreenState`'s internal lifecycle handling.

- [ ] **Step 1: Write the failing widget test**

`test/widget/tasks_screen_test.dart` already has `_buildTestRouter({String initialLocation = '/tasks'})` (a single-route `/tasks` `GoRouter`, no `StatefulShellRoute` needed) and `_pumpWithRouter(WidgetTester tester, GoRouter router, {ProviderContainer? container})` — reuse both directly:

```dart
  testWidgets(
    'search field updates when the route\'s q parameter changes '
    'while already mounted',
    (tester) async {
      final router = _buildTestRouter();
      await _pumpWithRouter(tester, router);

      router.go('/tasks?q=%23urgent');
      await tester.pumpAndSettle();

      expect(find.text('#urgent'), findsOneWidget);
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/tasks_screen_test.dart`
Expected: FAIL — the search field still shows its original (empty) text after the route changes.

- [ ] **Step 3: Implement the sync**

In `lib/features/task/widgets/tasks_screen.dart`, in `_TasksScreenState`, add:

```dart
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final urlQuery =
        GoRouter.maybeOf(context)?.state.uri.queryParameters['q'] ?? '';
    if (urlQuery != _searchController.text) {
      _searchController.value = TextEditingValue(
        text: urlQuery,
        selection: TextSelection.collapsed(offset: urlQuery.length),
      );
    }
  }
```

(Place it directly after `initState` for readability — `initState`'s existing seeding of `_searchController` from `params?['q']` can stay as-is; `didChangeDependencies` also runs once right after `initState`, so the two are redundant on first build but that's harmless — `urlQuery == _searchController.text` there, so the `if` is a no-op.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/tasks_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `flutter test`
Expected: PASS — in particular, re-run the existing tests around typing in the search field and confirm the field's own `_syncUrl()` writes don't fight with this new read (typing still updates the URL, which then round-trips back through `didChangeDependencies` as a no-op since the text already matches).

- [ ] **Step 6: Commit**

```bash
git add lib/features/task/widgets/tasks_screen.dart test/widget/tasks_screen_test.dart
git commit -m "fix: sync Tasks search field when the route's q param changes externally"
```

---

### Task 6: "Saved views" sidebar section — list and navigation

**Files:**
- Modify: `lib/core/widgets/app_shell.dart`
- Test: Create `test/widget/saved_views_sidebar_test.dart`

**Interfaces:**
- Consumes: `savedSearchListProvider` (Task 3), `SavedSearch` (Task 1).
- Produces (private to `app_shell.dart`, but named here since Tasks 7–8 extend them): `_SavedViewsSection extends ConsumerWidget` (constructor: `const new({required this.isNarrow})`), `_SavedViewRow extends ConsumerStatefulWidget` (constructor: `const new({required this.view, required this.index, required this.isNarrow, super.key})`).

**Context:** `app_shell.dart`'s `AppShell` is currently a plain `StatelessWidget`; `_drawerDestinations()` returns the fixed 4-item `List<NavigationDrawerDestination>` used as both the narrow `Drawer`'s and the wide sidebar's `NavigationDrawer.children`. `NavigationDrawer` only assigns `selectedIndex`/tap-index semantics to `NavigationDrawerDestination` children — other widget types in its `children` list are inert for that purpose, so appending a non-destination section after them is safe (this is standard Flutter M3 `NavigationDrawer` behavior — destinations and other widgets are tracked separately).

- [ ] **Step 1: Write the failing widget test**

```dart
// test/widget/saved_views_sidebar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/widgets/app_shell.dart';
import 'package:taskframe/features/saved_search/data/saved_search_repository.dart';
import 'package:taskframe/features/saved_search/providers.dart';

void _setViewportWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: '/tasks',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const Text('Day')),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tasks',
              builder: (context, state) => Text(
                'Tasks screen: q=${state.uri.queryParameters['q'] ?? ''}',
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<InMemorySavedSearchRepository> _seedOneView(WidgetTester tester) async {
  final repository = InMemorySavedSearchRepository();
  await repository.add(name: 'Urgent work', query: '#urgent');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        savedSearchRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(routerConfig: _buildRouter()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  group('Saved views sidebar', () {
    testWidgets('hidden when there are no saved views', (tester) async {
      _setViewportWidth(tester, 1000);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: _buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved views'), findsNothing);
    });

    testWidgets('shows each saved view by name, wide sidebar', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);
      await _seedOneView(tester);

      expect(find.text('Saved views'), findsOneWidget);
      expect(find.text('Urgent work'), findsOneWidget);
    });

    testWidgets('tapping a saved view loads its query into Tasks', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);
      await _seedOneView(tester);

      await tester.tap(find.text('Urgent work'));
      await tester.pumpAndSettle();

      expect(find.text('Tasks screen: q=#urgent'), findsOneWidget);
    });

    testWidgets('narrow: shows saved views in the open drawer', (
      tester,
    ) async {
      _setViewportWidth(tester, 600);
      await _seedOneView(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Urgent work'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/saved_views_sidebar_test.dart`
Expected: FAIL — no "Saved views" section exists yet.

- [ ] **Step 3: Implement the sidebar section**

In `lib/core/widgets/app_shell.dart`, add imports:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/saved_search/models/saved_search.dart';
import 'package:taskframe/features/saved_search/providers.dart';
```

Change both call sites that build `NavigationDrawer.children` to append the new section. In the narrow `Scaffold.drawer`:

```dart
          children: [..._drawerDestinations(), const _SavedViewsSection(isNarrow: true)],
```

In `_wideBody`'s `NavigationDrawer`:

```dart
            children: [..._drawerDestinations(), const _SavedViewsSection(isNarrow: false)],
```

Add at the bottom of the file:

```dart
/// The "Saved views" sidebar section, listed directly under the "Tasks"
/// destination — hidden entirely while there are no saved views.
class _SavedViewsSection extends ConsumerWidget {
  const new({required this.isNarrow});

  /// Whether this is rendered in the narrow (drawer) or wide (persistent
  /// sidebar) layout — controls whether tapping a view also closes the
  /// drawer, and whether row affordances reveal on long-press vs. hover.
  final bool isNarrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = ref.watch(savedSearchListProvider).value ?? const <SavedSearch>[];
    if (views.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 4),
          child: Text(
            'Saved views',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (var i = 0; i < views.length; i++)
          _SavedViewRow(
            key: ValueKey(views[i].id),
            view: views[i],
            index: i,
            isNarrow: isNarrow,
          ),
      ],
    );
  }
}

/// One row of [_SavedViewsSection]: tap navigates to the view's query;
/// rename/delete/reorder affordances are added in later tasks.
class _SavedViewRow extends ConsumerWidget {
  const new({
    required this.view,
    required this.index,
    required this.isNarrow,
    super.key,
  });

  final SavedSearch view;
  final int index;
  final bool isNarrow;

  void _navigate(BuildContext context) {
    if (isNarrow) Navigator.pop(context);
    context.go('/tasks?q=${Uri.encodeQueryComponent(view.query)}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 28, right: 16),
      title: Text(view.name, overflow: TextOverflow.ellipsis),
      onTap: () => _navigate(context),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/saved_views_sidebar_test.dart`
Expected: PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `flutter test`
Expected: PASS — in particular re-run `test/widget/app_shell_test.dart`, which uses a router with no `/tasks` branch and an empty (default in-memory) saved-views list, so the new section should render as `SizedBox.shrink()` there and change nothing.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/app_shell.dart test/widget/saved_views_sidebar_test.dart
git commit -m "feat: list saved views in the sidebar under Tasks"
```

---

### Task 7: Rename and delete via hover/long-press menu

**Files:**
- Modify: `lib/core/widgets/app_shell.dart`
- Test: `test/widget/saved_views_sidebar_test.dart` (extend)

**Interfaces:**
- Consumes: `SavedSearchListNotifier.renameView`/`deleteView` (Task 3); `_SavedViewRow` (Task 6, converted from `ConsumerWidget` to `ConsumerStatefulWidget` in this task).

**Behavior (from spec):** desktop (wide sidebar) reveals a trailing ⋮ menu on hover; narrow (drawer) reveals it on long-press. The ⋮ menu offers Rename (turns the label into an inline, autofocused `TextField`, submits on enter/blur) and Delete (immediate, no confirmation).

- [ ] **Step 1: Write the failing widget tests**

Add to `test/widget/saved_views_sidebar_test.dart`:

```dart
    testWidgets('wide: hovering a row reveals the overflow menu', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);
      await _seedOneView(tester);

      expect(find.byIcon(Icons.more_vert), findsNothing);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('Urgent work')));
      await tester.pump();

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('narrow: long-pressing a row reveals the overflow menu', (
      tester,
    ) async {
      _setViewportWidth(tester, 600);
      await _seedOneView(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert), findsNothing);
      await tester.longPress(find.text('Urgent work'));
      await tester.pump();

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('renaming a view updates its label', (tester) async {
      _setViewportWidth(tester, 600);
      await _seedOneView(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Urgent work'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'Renamed view');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Renamed view'), findsOneWidget);
      expect(find.text('Urgent work'), findsNothing);
    });

    testWidgets('deleting a view removes it from the sidebar', (
      tester,
    ) async {
      _setViewportWidth(tester, 600);
      await _seedOneView(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Urgent work'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Urgent work'), findsNothing);
      expect(find.text('Saved views'), findsNothing);
    });
```

Add the import this needs at the top of the file:

```dart
import 'package:flutter/gestures.dart' show PointerDeviceKind;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/saved_views_sidebar_test.dart`
Expected: FAIL — no overflow menu exists yet.

- [ ] **Step 3: Implement hover/long-press reveal, rename, and delete**

In `lib/core/widgets/app_shell.dart`, replace the `_SavedViewRow` class from Task 6 with:

```dart
/// One row of [_SavedViewsSection]. Tapping navigates to the view's
/// query. On wide layouts, hovering the row reveals a trailing overflow
/// menu (Rename/Delete); on narrow layouts, long-pressing does. Rename
/// swaps the label for an inline, autofocused text field.
class _SavedViewRow extends ConsumerStatefulWidget {
  const new({
    required this.view,
    required this.index,
    required this.isNarrow,
    super.key,
  });

  final SavedSearch view;
  final int index;
  final bool isNarrow;

  @override
  ConsumerState<_SavedViewRow> createState() => _SavedViewRowState();
}

class _SavedViewRowState extends ConsumerState<_SavedViewRow> {
  bool _revealed = false;
  bool _renaming = false;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.view.name);
  }

  @override
  void didUpdateWidget(covariant _SavedViewRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_renaming && oldWidget.view.name != widget.view.name) {
      _nameController.text = widget.view.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _navigate(BuildContext context) {
    if (widget.isNarrow) Navigator.pop(context);
    context.go('/tasks?q=${Uri.encodeQueryComponent(widget.view.query)}');
  }

  void _submitRename() {
    final newName = _nameController.text.trim();
    setState(() {
      _renaming = false;
      _revealed = false;
    });
    if (newName.isEmpty || newName == widget.view.name) {
      _nameController.text = widget.view.name;
      return;
    }
    ref.read(savedSearchListProvider.notifier).renameView(widget.view, newName);
  }

  @override
  Widget build(BuildContext context) {
    final showAffordances = _revealed || _renaming;

    final row = ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 28, right: 8),
      title: _renaming
          ? TextField(
              controller: _nameController,
              autofocus: true,
              onSubmitted: (_) => _submitRename(),
              onTapOutside: (_) => _submitRename(),
            )
          : Text(widget.view.name, overflow: TextOverflow.ellipsis),
      trailing: showAffordances
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (choice) {
                if (choice == 'rename') {
                  setState(() => _renaming = true);
                } else if (choice == 'delete') {
                  setState(() => _revealed = false);
                  ref
                      .read(savedSearchListProvider.notifier)
                      .deleteView(widget.view);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            )
          : null,
      onTap: _renaming ? null : () => _navigate(context),
      onLongPress: widget.isNarrow
          ? () => setState(() => _revealed = !_revealed)
          : null,
    );

    if (widget.isNarrow) return row;
    return MouseRegion(
      onEnter: (_) => setState(() => _revealed = true),
      onExit: (_) => setState(() => _revealed = false),
      child: row,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/saved_views_sidebar_test.dart`
Expected: PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `flutter test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/app_shell.dart test/widget/saved_views_sidebar_test.dart
git commit -m "feat: add rename and delete to saved view sidebar rows"
```

---

### Task 8: Drag-to-reorder saved views

**Files:**
- Modify: `lib/core/widgets/app_shell.dart`
- Test: `test/widget/saved_views_sidebar_test.dart` (extend)

**Interfaces:**
- Consumes: `SavedSearchListNotifier.reorder(int oldIndex, int newIndex)` (Task 3).

**Behavior (from spec):** the saved-views list is a `ReorderableListView`; each row exposes a drag handle (rather than the whole row being draggable, so a plain tap still just navigates). Dragging calls `reorder`.

- [ ] **Step 1: Write the failing widget test**

Add to `test/widget/saved_views_sidebar_test.dart`. `ReorderableListView` drag gestures are awkward to simulate directly in a widget test; test the underlying behavior instead by driving the notifier and asserting the sidebar reflects the new order (already effectively covered by Task 3's unit tests) plus a widget-level smoke test that a drag handle exists and dragging it reorders the rows:

```dart
    testWidgets('two saved views can be reordered by dragging the handle', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);
      final repository = InMemorySavedSearchRepository();
      await repository.add(name: 'First', query: '#a');
      await repository.add(name: 'Second', query: '#b');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedSearchRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(routerConfig: _buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      final firstHandleFinder = find.byIcon(Icons.drag_indicator).first;
      final secondRowFinder = find.text('Second');
      await tester.drag(
        firstHandleFinder,
        tester.getCenter(secondRowFinder) - tester.getCenter(firstHandleFinder),
      );
      await tester.pumpAndSettle();

      final rowTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((t) => t == 'First' || t == 'Second')
          .toList();
      expect(rowTexts, ['Second', 'First']);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/saved_views_sidebar_test.dart`
Expected: FAIL — no drag handle exists yet, and rows aren't reorderable.

- [ ] **Step 3: Implement drag-to-reorder**

In `lib/core/widgets/app_shell.dart`, replace `_SavedViewsSection.build`'s row list with a `ReorderableListView`:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = ref.watch(savedSearchListProvider).value ?? const <SavedSearch>[];
    if (views.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 4),
          child: Text(
            'Saved views',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (oldIndex, newIndex) => ref
              .read(savedSearchListProvider.notifier)
              .reorder(oldIndex, newIndex),
          children: [
            for (var i = 0; i < views.length; i++)
              _SavedViewRow(
                key: ValueKey(views[i].id),
                view: views[i],
                index: i,
                isNarrow: isNarrow,
              ),
          ],
        ),
      ],
    );
  }
```

In `_SavedViewRowState.build`, wrap the `PopupMenuButton` (when `showAffordances`) together with a drag handle in a `Row`, using `ReorderableDragStartListener` bound to `widget.index`:

```dart
      trailing: showAffordances
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: widget.index,
                  child: const Icon(Icons.drag_indicator, size: 18),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (choice) {
                    if (choice == 'rename') {
                      setState(() => _renaming = true);
                    } else if (choice == 'delete') {
                      setState(() => _revealed = false);
                      ref
                          .read(savedSearchListProvider.notifier)
                          .deleteView(widget.view);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            )
          : null,
```

(This replaces the earlier bare `PopupMenuButton` trailing widget from Task 7 — same `onSelected` body, now alongside the drag handle.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/saved_views_sidebar_test.dart`
Expected: PASS

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `flutter test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/app_shell.dart test/widget/saved_views_sidebar_test.dart
git commit -m "feat: drag-to-reorder saved views in the sidebar"
```

---

## Final check

- [ ] Run `flutter analyze` and fix any lints introduced by the new files.
- [ ] Run the full suite once more: `flutter test`.
- [ ] Manually verify in a running app (`flutter run -d web-server --web-port=8080`, per project convention): type a search, star it, confirm it appears under Tasks in the sidebar, rename it, reorder a second one above it, delete one, and confirm the star toggles correctly when reselecting a pinned query.
