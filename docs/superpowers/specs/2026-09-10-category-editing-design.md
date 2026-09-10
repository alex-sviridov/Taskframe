# Category editing view

## Purpose

Add a standalone view for managing categories: create, edit, and delete
categories, editing their color and emoji. A single default category always
exists, is listed first, cannot be deleted, and only its color can be
changed. Applying categories to blocks is explicitly out of scope — this
work only builds the management view and its backing data.

## Scope

In scope:
- `Category` data model
- In-memory repository + Riverpod provider for categories, following the
  existing `DayBlocksRepository`/`dayBlocksProvider` pattern
- A `/categories` route and screen for listing, adding, editing, and
  deleting categories
- Color and emoji pickers backed by third-party packages
- Widget tests for the new screen

Out of scope:
- Associating categories with blocks (`TimeObject`) or any block UI
- Persisting categories to disk (matches `DayBlocksRepository`: in-memory
  only, reset on app restart)
- Any navigation entry point into `/categories` from the rest of the app
  (reached by route only, e.g. in tests or direct navigation)
- Reordering categories

## Data model

`lib/features/category/models/category.dart`:

```dart
class Category {
  static const String defaultId = '0';

  final String id;
  final String name;
  final int colorValue; // ARGB32, e.g. Color.toARGB32()
  final String? emoji;  // null for the default category

  bool get isDefault => id == defaultId;
}
```

Immutable, with a `copyWith`, mirroring `TimeObject`'s style. The default
category is identified purely by `id == Category.defaultId` — no separate
flag. Its `emoji` is always `null` and its `name` is fixed (e.g.
`"Default"`); the UI enforces this by disabling those fields when editing
it, and the repository defensively ignores attempts to change the default
category's name/emoji or to delete it.

## Repository

`lib/features/category/data/category_repository.dart`, matching
`DayBlocksRepository`'s shape:

```dart
abstract class CategoryRepository {
  Future<List<Category>> load();
  Future<Category> add({required String name, required int colorValue, String? emoji});
  Future<Category> update(Category category, {String? name, int? colorValue, String? emoji});
  Future<void> delete(Category category);
}
```

`InMemoryCategoryRepository`:
- Seeded with one default category (`id: Category.defaultId`, fixed name,
  a default color, `emoji: null`).
- `delete` is a no-op (or throws, TBD by implementer's judgment — no
  observable difference since the UI never offers delete for it) when
  called with the default category's id.
- `update` on the default category ignores any `name`/`emoji` argument and
  only applies `colorValue`.
- New categories get generated ids the same way `InMemoryDayBlocksRepository`
  generates block ids (an incrementing counter), never `'0'`.

## Providers

`lib/features/category/providers.dart`:

- `categoryRepositoryProvider` — `Provider<CategoryRepository>` returning
  `InMemoryCategoryRepository()`, same pattern as `dayBlocksRepositoryProvider`.
- `CategoryListNotifier extends AsyncNotifier<List<Category>>` — loads via
  the repository in `build()`, exposes `addCategory`, `updateCategory`,
  `deleteCategory`, each calling the repository then updating `state`
  in place (same style as `DayBlocksNotifier`).
- `categoryListProvider` — `AsyncNotifierProvider<CategoryListNotifier, List<Category>>`.

## UI

`lib/features/category/widgets/categories_screen.dart`:

- `CategoriesScreen`: a `Scaffold` with an app bar ("Categories") and a
  `ListView` of category rows. Each row shows the emoji (or a placeholder
  for the default category, which has none), a color swatch, and the name.
  The default category is always first (the repository/provider already
  returns it first since it's seeded first and never reordered).
  - Non-default rows have a trailing delete icon button that opens an
    `AlertDialog` ("Delete this category?" / Cancel / Delete) before
    calling `deleteCategory`.
  - The default row has no delete icon.
  - An app bar action (`+` icon) opens the edit sheet in "create" mode.
  - Tapping any row opens the edit sheet in "edit" mode for that category.
- `CategoryEditSheet` (modal bottom sheet, consistent with
  `block_edit_modal.dart`'s use of sheets): a name `TextField` (disabled,
  showing the fixed name, when editing the default category), a color
  swatch button that opens `flutter_colorpicker`'s `ColorPicker` inside an
  `AlertDialog`, and — omitted entirely when editing the default category —
  an emoji button that opens `emoji_picker_flutter`'s `EmojiPicker` in a
  bottom sheet. Save/Cancel buttons; Save is disabled while the name is
  empty (for non-default categories, where the name is editable).

## Route

Add to `lib/router.dart`:

```dart
GoRoute(path: '/categories', builder: (context, state) => const CategoriesScreen()),
```

alongside the existing `/` route. No link to it is added anywhere else in
the app (out of scope).

## Dependencies

Add to `pubspec.yaml`:
- `flutter_colorpicker` — color selection
- `emoji_picker_flutter` — emoji selection

## Testing

`test/widget/categories_screen_test.dart`, mocking `CategoryRepository`
with `mocktail` the way existing widget tests mock `DayBlocksRepository`:
- Default category renders first, with no delete affordance.
- Adding a category (name + color + emoji) shows it in the list.
- Editing a non-default category's name/color/emoji persists via the
  repository and updates the row.
- Editing the default category only offers a color change (no name field
  input, no emoji button).
- Deleting a non-default category asks for confirmation; confirming
  removes it, canceling leaves it.
