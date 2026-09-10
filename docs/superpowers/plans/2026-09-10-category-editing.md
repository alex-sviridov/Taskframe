# Category Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone `/categories` view for creating, editing, and deleting categories (name, color, emoji), with one permanent default category (id `'0'`) whose name and emoji are fixed and only its color can be changed.

**Architecture:** A `Category` model + `CategoryRepository`/`InMemoryCategoryRepository` + Riverpod `AsyncNotifier`, mirroring the existing `TimeObject`/`DayBlocksRepository`/`DayBlocksNotifier` stack exactly. A `CategoriesScreen` lists categories and opens a `CategoryEditSheet` (bottom sheet) for add/edit, using `flutter_colorpicker`'s `BlockPicker` and `emoji_picker_flutter`'s `EmojiPicker`. Reached only via a new `/categories` route — no link from elsewhere in the app.

**Tech Stack:** Flutter 3.47, Riverpod (`flutter_riverpod` ^3.4.3), `go_router` ^18.0.1, `flutter_colorpicker` ^1.1.0, `emoji_picker_flutter` ^4.5.4.

**Spec:** `docs/superpowers/specs/2026-09-10-category-editing-design.md`

## Global Constraints

- In-memory persistence only — categories reset on app restart, matching `InMemoryDayBlocksRepository`. No disk persistence.
- The default category's id is the hardcoded constant `Category.defaultId = '0'`; it is identified by `id == Category.defaultId`, never a separate boolean flag.
- The default category's name is fixed (`'Default'`) and its `emoji` is always `null`; only its `colorValue` is editable.
- No navigation entry point into `/categories` is added anywhere else in the app — reached by route only.
- No reordering of categories; list order is insertion order with the default category always first.
- Associating categories with blocks (`TimeObject`) is out of scope — do not touch `lib/features/day/**`.
- Follow existing code style: no comments except where a non-obvious WHY needs explaining (see `day_blocks_repository.dart`, `providers.dart` for the house style), full dartdoc on public members (`very_good_analysis` lint set is enabled).

---

### Task 1: Add color and emoji picker dependencies

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: `flutter_colorpicker` (`BlockPicker` widget) and `emoji_picker_flutter` (`EmojiPicker` widget, `Emoji`/`Category`/`OnEmojiSelected` types) available to import in later tasks.

- [ ] **Step 1: Add the dependencies**

Run:
```bash
flutter pub add flutter_colorpicker emoji_picker_flutter
```

This adds `flutter_colorpicker: ^1.1.0` and `emoji_picker_flutter: ^4.5.4` to `pubspec.yaml`'s `dependencies:` section and updates `pubspec.lock`.

- [ ] **Step 2: Verify the app still analyzes cleanly**

Run: `flutter analyze`
Expected: No new errors (pre-existing warnings, if any, are unrelated to this change).

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "Add flutter_colorpicker and emoji_picker_flutter dependencies"
```

---

### Task 2: Category model

**Files:**
- Create: `lib/features/category/models/category.dart`
- Test: `test/unit/category_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class Category {
    static const String defaultId = '0';

    const Category({
      required this.id,
      required this.name,
      required this.colorValue,
      this.emoji,
    });

    final String id;
    final String name;
    final int colorValue;
    final String? emoji;

    bool get isDefault => id == defaultId;

    Category copyWith({String? name, int? colorValue, String? emoji});
  }
  ```
  `colorValue` is an ARGB32 int, e.g. produced by `Color.toARGB32()`. `copyWith`'s `emoji` parameter replaces the emoji outright (including clearing it back to `null` is not supported via `copyWith` — callers needing to clear it construct a new `Category` directly); this matches the fact only non-default categories ever have their emoji touched by UI code, and they never clear it back to `null`.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/category_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';

void main() {
  group('Category', () {
    test('isDefault is true when id equals Category.defaultId', () {
      const category = Category(
        id: Category.defaultId,
        name: 'Default',
        colorValue: 0xFF009688,
      );

      expect(category.isDefault, isTrue);
    });

    test('isDefault is false for any other id', () {
      const category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      expect(category.isDefault, isFalse);
    });

    test('copyWith replaces only the given fields', () {
      const category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      final updated = category.copyWith(name: 'Career', colorValue: 0xFFFF0000);

      expect(updated.id, 'category-1');
      expect(updated.name, 'Career');
      expect(updated.colorValue, 0xFFFF0000);
      expect(updated.emoji, '💼');
    });

    test('copyWith with no arguments returns equivalent fields', () {
      const category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      final copy = category.copyWith();

      expect(copy.id, category.id);
      expect(copy.name, category.name);
      expect(copy.colorValue, category.colorValue);
      expect(copy.emoji, category.emoji);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/category_test.dart`
Expected: FAIL — `lib/features/category/models/category.dart` doesn't exist yet (import error).

- [ ] **Step 3: Write the implementation**

Create `lib/features/category/models/category.dart`:

```dart
/// A category blocks can be tagged with (application to blocks is out of
/// scope for this model — it exists purely for the category management
/// view).
class Category {
  /// Creates a [Category].
  const Category({
    required this.id,
    required this.name,
    required this.colorValue,
    this.emoji,
  });

  /// The id of the single, permanent default category. Identifying it by
  /// this constant (rather than a separate boolean flag) keeps "is this
  /// the default" a single source of truth.
  static const String defaultId = '0';

  /// Unique identifier for this category.
  final String id;

  /// Display name. Fixed for the default category.
  final String name;

  /// The category's color, as an ARGB32 value (e.g. `Color.toARGB32()`).
  final int colorValue;

  /// The category's emoji, or `null` for the default category, which has
  /// none.
  final String? emoji;

  /// Whether this is the single, permanent default category.
  bool get isDefault => id == defaultId;

  /// Returns a copy of this category with any of [name]/[colorValue]/
  /// [emoji] replaced.
  Category copyWith({String? name, int? colorValue, String? emoji}) =>
      Category(
        id: id,
        name: name ?? this.name,
        colorValue: colorValue ?? this.colorValue,
        emoji: emoji ?? this.emoji,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/category_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/category/models/category.dart test/unit/category_test.dart
git commit -m "Add Category model"
```

---

### Task 3: CategoryRepository and InMemoryCategoryRepository

**Files:**
- Create: `lib/features/category/data/category_repository.dart`
- Test: `test/unit/category_repository_test.dart`

**Interfaces:**
- Consumes: `Category`, `Category.defaultId` from Task 2 (`package:taskframe/features/category/models/category.dart`).
- Produces:
  ```dart
  abstract class CategoryRepository {
    Future<List<Category>> load();
    Future<Category> add({required String name, required int colorValue, String? emoji});
    Future<Category> update(Category category, {String? name, int? colorValue, String? emoji});
    Future<void> delete(Category category);
  }

  class InMemoryCategoryRepository implements CategoryRepository { ... }
  ```
  `load()` always returns the default category first, followed by added categories in insertion order. `update` on the default category ignores `name`/`emoji` and only applies `colorValue`. `delete` on the default category is a no-op. `add` never assigns the id `Category.defaultId`.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/category_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/data/category_repository.dart';
import 'package:taskframe/features/category/models/category.dart';

void main() {
  group('InMemoryCategoryRepository', () {
    late InMemoryCategoryRepository repository;

    setUp(() => repository = InMemoryCategoryRepository());

    test('load returns exactly one seeded default category', () async {
      final categories = await repository.load();

      expect(categories, hasLength(1));
      expect(categories.single.isDefault, isTrue);
    });

    test('the default category has a fixed name and no emoji', () async {
      final categories = await repository.load();

      expect(categories.single.name, 'Default');
      expect(categories.single.emoji, isNull);
    });

    test('add appends a new non-default category', () async {
      final added = await repository.add(
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      expect(added.isDefault, isFalse);
      expect(added.name, 'Work');
      expect(added.colorValue, 0xFF2196F3);
      expect(added.emoji, '💼');
    });

    test('an added category shows up in a later load, after the default', () async {
      await repository.add(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');

      final categories = await repository.load();

      expect(categories, hasLength(2));
      expect(categories.first.isDefault, isTrue);
      expect(categories.last.name, 'Work');
    });

    test('two added categories get distinct, non-default ids', () async {
      final first = await repository.add(name: 'Work', colorValue: 0xFF2196F3);
      final second = await repository.add(name: 'Health', colorValue: 0xFF4CAF50);

      expect(first.id, isNot(equals(second.id)));
      expect(first.id, isNot(Category.defaultId));
      expect(second.id, isNot(Category.defaultId));
    });

    test('update changes an added category\'s name, color and emoji', () async {
      final added = await repository.add(name: 'Work', colorValue: 0xFF2196F3);

      final updated = await repository.update(
        added,
        name: 'Career',
        colorValue: 0xFFFF0000,
        emoji: '🚀',
      );

      expect(updated.id, added.id);
      expect(updated.name, 'Career');
      expect(updated.colorValue, 0xFFFF0000);
      expect(updated.emoji, '🚀');
    });

    test('update leaves fields unspecified as null unchanged', () async {
      final added = await repository.add(
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      final updated = await repository.update(added, colorValue: 0xFFFF0000);

      expect(updated.name, 'Work');
      expect(updated.emoji, '💼');
    });

    test('update replaces the category in a later load', () async {
      final added = await repository.add(name: 'Work', colorValue: 0xFF2196F3);

      await repository.update(added, name: 'Career');

      final categories = await repository.load();
      expect(categories.singleWhere((c) => c.id == added.id).name, 'Career');
    });

    test('updating the default category only applies the color change', () async {
      final defaultCategory = (await repository.load()).single;

      final updated = await repository.update(
        defaultCategory,
        name: 'Renamed',
        colorValue: 0xFFFF0000,
        emoji: '🔥',
      );

      expect(updated.name, 'Default');
      expect(updated.emoji, isNull);
      expect(updated.colorValue, 0xFFFF0000);
    });

    test('delete removes an added category from a later load', () async {
      final added = await repository.add(name: 'Work', colorValue: 0xFF2196F3);

      await repository.delete(added);

      final categories = await repository.load();
      expect(categories.where((c) => c.id == added.id), isEmpty);
    });

    test('delete on the default category is a no-op', () async {
      final defaultCategory = (await repository.load()).single;

      await repository.delete(defaultCategory);

      final categories = await repository.load();
      expect(categories, hasLength(1));
      expect(categories.single.isDefault, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/category_repository_test.dart`
Expected: FAIL — `lib/features/category/data/category_repository.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/features/category/data/category_repository.dart`:

```dart
import 'package:taskframe/features/category/models/category.dart';

/// Loads and stores categories.
///
/// Implementations back this with whatever storage is appropriate (in
/// memory today, an API later); callers depend only on this interface.
abstract class CategoryRepository {
  /// Returns all categories, with the default category always first.
  Future<List<Category>> load();

  /// Creates a new, non-default category and returns it.
  Future<Category> add({
    required String name,
    required int colorValue,
    String? emoji,
  });

  /// Updates [category] in place, replacing any of [name]/[colorValue]/
  /// [emoji] that are given and leaving the rest unchanged. Returns the
  /// updated category.
  ///
  /// If [category] is the default category, [name] and [emoji] are
  /// ignored — only [colorValue] is ever applied to it.
  Future<Category> update(
    Category category, {
    String? name,
    int? colorValue,
    String? emoji,
  });

  /// Removes [category]. A no-op if [category] is the default category.
  Future<void> delete(Category category);
}

/// A [CategoryRepository] that keeps categories in memory for the life of
/// the app, seeded with a single default category.
class InMemoryCategoryRepository implements CategoryRepository {
  final List<Category> _added = [];
  int _nextId = 1;

  Category _defaultCategory = const Category(
    id: Category.defaultId,
    name: 'Default',
    colorValue: 0xFF009688,
  );

  @override
  Future<List<Category>> load() async => [_defaultCategory, ..._added];

  @override
  Future<Category> add({
    required String name,
    required int colorValue,
    String? emoji,
  }) async {
    final category = Category(
      id: 'category-${_nextId++}',
      name: name,
      colorValue: colorValue,
      emoji: emoji,
    );
    _added.add(category);
    return category;
  }

  @override
  Future<Category> update(
    Category category, {
    String? name,
    int? colorValue,
    String? emoji,
  }) async {
    if (category.isDefault) {
      _defaultCategory = _defaultCategory.copyWith(colorValue: colorValue);
      return _defaultCategory;
    }

    final index = _added.indexWhere((c) => c.id == category.id);
    final updated = _added[index].copyWith(
      name: name,
      colorValue: colorValue,
      emoji: emoji,
    );
    _added[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(Category category) async {
    if (category.isDefault) return;
    _added.removeWhere((c) => c.id == category.id);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/category_repository_test.dart`
Expected: PASS (11 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/category/data/category_repository.dart test/unit/category_repository_test.dart
git commit -m "Add CategoryRepository and InMemoryCategoryRepository"
```

---

### Task 4: Category providers

**Files:**
- Create: `lib/features/category/providers.dart`
- Test: `test/unit/category_providers_test.dart`

**Interfaces:**
- Consumes: `Category`, `CategoryRepository`, `InMemoryCategoryRepository` from Tasks 2–3.
- Produces:
  ```dart
  final categoryRepositoryProvider = Provider<CategoryRepository>(...);

  class CategoryListNotifier extends AsyncNotifier<List<Category>> {
    Future<Category> addCategory({required String name, required int colorValue, String? emoji});
    Future<void> updateCategory(Category category, {String? name, int? colorValue, String? emoji});
    Future<void> deleteCategory(Category category);
  }

  final categoryListProvider = AsyncNotifierProvider<CategoryListNotifier, List<Category>>(...);
  ```
  Later UI tasks read/write categories only through `categoryListProvider`.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/category_providers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/data/category_repository.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';

void main() {
  group('categoryListProvider', () {
    test('loads the repository categories', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final categories = await container.read(categoryListProvider.future);
      final expected = await InMemoryCategoryRepository().load();

      expect(categories.map((c) => c.id), expected.map((c) => c.id));
    });

    test('addCategory appends the new category returned by the repository', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);

      await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');

      final categories = container.read(categoryListProvider).value!;
      expect(categories.where((c) => c.name == 'Work'), hasLength(1));
    });

    test('addCategory returns the created category', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);

      final created = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');

      expect(created.name, 'Work');
      expect(created.emoji, '💼');
    });

    test('updateCategory persists a name/color/emoji change', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      final created = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3);

      await container
          .read(categoryListProvider.notifier)
          .updateCategory(created, name: 'Career', colorValue: 0xFFFF0000);

      final categories = container.read(categoryListProvider).value!;
      final updated = categories.singleWhere((c) => c.id == created.id);
      expect(updated.name, 'Career');
      expect(updated.colorValue, 0xFFFF0000);
    });

    test('deleteCategory removes the category from state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      final created = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3);

      await container.read(categoryListProvider.notifier).deleteCategory(created);

      final categories = container.read(categoryListProvider).value!;
      expect(categories.where((c) => c.id == created.id), isEmpty);
    });

    test('deleteCategory on the default category leaves it in state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final categories = await container.read(categoryListProvider.future);
      final defaultCategory = categories.single;

      await container
          .read(categoryListProvider.notifier)
          .deleteCategory(defaultCategory);

      final after = container.read(categoryListProvider).value!;
      expect(after, hasLength(1));
      expect(after.single.isDefault, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/category_providers_test.dart`
Expected: FAIL — `lib/features/category/providers.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/features/category/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/category/data/category_repository.dart';
import 'package:taskframe/features/category/models/category.dart';

/// The backing store for categories.
///
/// Overriding this single provider (e.g. with an API-backed
/// [CategoryRepository]) is enough to change where categories are loaded
/// from and saved to; nothing downstream needs to change.
final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => InMemoryCategoryRepository(),
);

/// Holds the list of categories, loaded from [categoryRepositoryProvider],
/// and lets consumers add/update/delete them.
class CategoryListNotifier extends AsyncNotifier<List<Category>> {
  @override
  Future<List<Category>> build() =>
      ref.watch(categoryRepositoryProvider).load();

  /// Creates a new category, adds it to the current state, and returns it.
  Future<Category> addCategory({
    required String name,
    required int colorValue,
    String? emoji,
  }) async {
    final repository = ref.read(categoryRepositoryProvider);
    final added = await repository.add(
      name: name,
      colorValue: colorValue,
      emoji: emoji,
    );
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Updates [category]'s name/color/emoji, persisting via the repository
  /// and refreshing state.
  Future<void> updateCategory(
    Category category, {
    String? name,
    int? colorValue,
    String? emoji,
  }) async {
    final repository = ref.read(categoryRepositoryProvider);
    final updated = await repository.update(
      category,
      name: name,
      colorValue: colorValue,
      emoji: emoji,
    );
    state = AsyncData([
      for (final c in state.value ?? <Category>[])
        if (c.id == category.id) updated else c,
    ]);
  }

  /// Removes [category], persisting via the repository and refreshing
  /// state. A no-op if [category] is the default category.
  Future<void> deleteCategory(Category category) async {
    final repository = ref.read(categoryRepositoryProvider);
    await repository.delete(category);
    state = AsyncData([
      for (final c in state.value ?? <Category>[])
        if (c.id != category.id || category.isDefault) c,
    ]);
  }
}

/// The list of categories.
final categoryListProvider =
    AsyncNotifierProvider<CategoryListNotifier, List<Category>>(
      CategoryListNotifier.new,
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/category_providers_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/category/providers.dart test/unit/category_providers_test.dart
git commit -m "Add category providers"
```

---

### Task 5: CategoryEditSheet widget

**Files:**
- Create: `lib/features/category/widgets/category_edit_sheet.dart`
- Test: `test/widget/category_edit_sheet_test.dart`

**Interfaces:**
- Consumes: `Category`, `categoryListProvider`/`CategoryListNotifier` from Tasks 2 and 4; `BlockPicker` from `package:flutter_colorpicker/flutter_colorpicker.dart`; `EmojiPicker`, `Emoji`, `OnEmojiSelected` from `package:emoji_picker_flutter/emoji_picker_flutter.dart`.
- Produces:
  ```dart
  /// Opens the edit sheet for [category] (edit mode) or, when [category] is
  /// null, for creating a new category (create mode). Returns after the
  /// sheet is dismissed either way (Save or Cancel/scrim tap); callers don't
  /// need a return value since the notifier already updated state.
  Future<void> showCategoryEditSheet({
    required BuildContext context,
    required WidgetRef ref,
    Category? category,
  });
  ```
  Later `CategoriesScreen` task calls `showCategoryEditSheet` directly — it does not build its own sheet UI.

- [ ] **Step 1: Write the failing tests**

Create `test/widget/category_edit_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_edit_sheet.dart';

Future<ProviderContainer> _seededContainer() async {
  final container = ProviderContainer();
  await container.read(categoryListProvider.future);
  return container;
}

Future<void> _pumpOpenButton(
  WidgetTester tester,
  ProviderContainer container, {
  Category? category,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () => showCategoryEditSheet(
              context: context,
              ref: ref,
              category: category,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('CategoryEditSheet', () {
    testWidgets('create mode: entering a name and saving adds a category', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Work');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final categories = container.read(categoryListProvider).value!;
      expect(categories.where((c) => c.name == 'Work'), hasLength(1));
    });

    testWidgets('create mode: Save is disabled while the name is empty', (
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

    testWidgets('create mode: shows both a color swatch and an emoji button', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('categoryEditSheet.colorSwatch')), findsOneWidget);
      expect(find.byKey(const Key('categoryEditSheet.emojiButton')), findsOneWidget);
    });

    testWidgets('edit mode: pre-fills the name field with the category name', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      await _pumpOpenButton(tester, container, category: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('edit mode: changing the name and saving persists it', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      await _pumpOpenButton(tester, container, category: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Career');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final categories = container.read(categoryListProvider).value!;
      expect(categories.singleWhere((c) => c.id == created.id).name, 'Career');
    });

    testWidgets(
      'edit mode on the default category: name field is disabled and no '
      'emoji button is shown',
      (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final categories = container.read(categoryListProvider).value!;
        final defaultCategory = categories.single;
        await _pumpOpenButton(tester, container, category: defaultCategory);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final nameField = tester.widget<TextField>(find.byType(TextField));
        expect(nameField.enabled, isFalse);
        expect(
          find.byKey(const Key('categoryEditSheet.emojiButton')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('categoryEditSheet.colorSwatch')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'edit mode on the default category: saving only persists the color',
      (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final categories = container.read(categoryListProvider).value!;
        final defaultCategory = categories.single;
        await _pumpOpenButton(tester, container, category: defaultCategory);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final after = container.read(categoryListProvider).value!;
        expect(after.single.name, 'Default');
        expect(after.single.emoji, isNull);
      },
    );

    testWidgets('Cancel dismisses the sheet without saving changes', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Work');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final categories = container.read(categoryListProvider).value!;
      expect(categories.where((c) => c.name == 'Work'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/category_edit_sheet_test.dart`
Expected: FAIL — `lib/features/category/widgets/category_edit_sheet.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/features/category/widgets/category_edit_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';

/// Opens the edit sheet for [category] (edit mode) or, when [category] is
/// `null`, for creating a new category (create mode).
Future<void> showCategoryEditSheet({
  required BuildContext context,
  required WidgetRef ref,
  Category? category,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _CategoryEditSheetContent(category: category),
  );
}

class _CategoryEditSheetContent extends ConsumerStatefulWidget {
  const _CategoryEditSheetContent({this.category});

  final Category? category;

  @override
  ConsumerState<_CategoryEditSheetContent> createState() =>
      _CategoryEditSheetContentState();
}

class _CategoryEditSheetContentState
    extends ConsumerState<_CategoryEditSheetContent> {
  late final TextEditingController _nameController;
  late Color _color;
  String? _emoji;

  bool get _isDefault => widget.category?.isDefault ?? false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _color = Color(widget.category?.colorValue ?? 0xFF009688);
    _emoji = widget.category?.emoji;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) {
        var dialogColor = _color;
        return AlertDialog(
          content: BlockPicker(
            pickerColor: _color,
            onColorChanged: (color) => dialogColor = color,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(dialogColor),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
    if (picked != null) setState(() => _color = picked);
  }

  Future<void> _pickEmoji() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SizedBox(
        height: 300,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) =>
              Navigator.of(context).pop(emoji.emoji),
        ),
      ),
    );
    if (picked != null) setState(() => _emoji = picked);
  }

  Future<void> _save() async {
    final notifier = ref.read(categoryListProvider.notifier);
    if (widget.category == null) {
      await notifier.addCategory(
        name: _nameController.text,
        colorValue: _color.toARGB32(),
        emoji: _emoji,
      );
    } else {
      await notifier.updateCategory(
        widget.category!,
        name: _nameController.text,
        colorValue: _color.toARGB32(),
        emoji: _emoji,
      );
    }
    if (mounted) Navigator.of(context).pop();
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
              controller: _nameController,
              enabled: !_isDefault,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                GestureDetector(
                  key: const Key('categoryEditSheet.colorSwatch'),
                  onTap: _pickColor,
                  child: CircleAvatar(backgroundColor: _color),
                ),
                if (!_isDefault) ...[
                  const SizedBox(width: 16),
                  IconButton(
                    key: const Key('categoryEditSheet.emojiButton'),
                    onPressed: _pickEmoji,
                    icon: Text(
                      _emoji ?? '➕',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: (_isDefault || _nameController.text.isNotEmpty)
                      ? _save
                      : null,
                  child: const Text('Save'),
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

Run: `flutter test test/widget/category_edit_sheet_test.dart`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/category/widgets/category_edit_sheet.dart test/widget/category_edit_sheet_test.dart
git commit -m "Add CategoryEditSheet"
```

---

### Task 6: CategoriesScreen, route, and screen widget tests

**Files:**
- Create: `lib/features/category/widgets/categories_screen.dart`
- Modify: `lib/router.dart`
- Test: `test/widget/categories_screen_test.dart`

**Interfaces:**
- Consumes: `Category`, `categoryListProvider` (Tasks 2, 4); `showCategoryEditSheet` (Task 5).
- Produces: `CategoriesScreen` widget (a `ConsumerWidget`), and the `/categories` route in `appRouter`.

- [ ] **Step 1: Write the failing tests**

Create `test/widget/categories_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/categories_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: CategoriesScreen())),
  );
  await tester.pump();
}

void main() {
  group('CategoriesScreen', () {
    testWidgets('shows the default category first, with no delete icon', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Default'), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsNothing);
    });

    testWidgets('adding a category via the app bar action shows it in the list', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Work');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('tapping a non-default category row opens it in edit mode', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Career');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Career'), findsOneWidget);
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('deleting a non-default category asks for confirmation', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('confirming the delete dialog removes the category', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsNothing);
    });

    testWidgets('canceling the delete dialog leaves the category', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/categories_screen_test.dart`
Expected: FAIL — `lib/features/category/widgets/categories_screen.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/features/category/widgets/categories_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_edit_sheet.dart';

/// Lists all categories and lets the user add, edit, or delete them. The
/// default category is always first and has no delete affordance.
class CategoriesScreen extends ConsumerWidget {
  /// Creates a [CategoriesScreen].
  const CategoriesScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this category?'),
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
    if (confirmed ?? false) {
      await ref.read(categoryListProvider.notifier).deleteCategory(category);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoryListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () =>
                showCategoryEditSheet(context: context, ref: ref),
          ),
        ],
      ),
      body: switch (categoriesAsync) {
        AsyncData(:final value) => ListView(
          children: [
            for (final category in value)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(category.colorValue),
                  child: category.emoji != null
                      ? Text(category.emoji!)
                      : null,
                ),
                title: Text(category.name),
                onTap: () => showCategoryEditSheet(
                  context: context,
                  ref: ref,
                  category: category,
                ),
                trailing: category.isDefault
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () =>
                            _confirmDelete(context, ref, category),
                      ),
              ),
          ],
        ),
        AsyncError() => const Center(child: Text('Failed to load categories')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
```

- [ ] **Step 4: Wire up the route**

Modify `lib/router.dart`:

```dart
import 'package:go_router/go_router.dart';
import 'package:taskframe/features/category/widgets/categories_screen.dart';
import 'package:taskframe/features/day/day_screen.dart';

/// Application router with the single smoke-test route.
final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const DayScreen()),
    GoRoute(
      path: '/categories',
      builder: (context, state) => const CategoriesScreen(),
    ),
  ],
);
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/widget/categories_screen_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests, including the pre-existing day/* suites, unaffected)

- [ ] **Step 7: Run analyze**

Run: `flutter analyze`
Expected: No new errors.

- [ ] **Step 8: Commit**

```bash
git add lib/features/category/widgets/categories_screen.dart lib/router.dart test/widget/categories_screen_test.dart
git commit -m "Add CategoriesScreen and /categories route"
```

---

## Self-Review Notes

- **Spec coverage:** model (Task 2), repository (Task 3), providers (Task 4), color/emoji pickers via named packages (Tasks 1, 5), default category fixed-name/no-emoji/color-only editing (Tasks 2–6), delete confirmation (Task 6), route with no other entry point (Task 6), in-memory-only persistence (Tasks 3–4), no reordering (list order is seed-then-insertion throughout) — all covered.
- **Type consistency:** `colorValue` (`int`, ARGB32) is used consistently from `Category` (Task 2) through `CategoryRepository`/`InMemoryCategoryRepository` (Task 3), `CategoryListNotifier` (Task 4), and both widgets (Tasks 5–6). `Category.defaultId` / `isDefault` used consistently as the sole default-detection mechanism everywhere, never a separate flag.
- **No placeholders:** every task's implementation step is complete, runnable code; no TBD/TODO.
