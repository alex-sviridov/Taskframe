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

/// Returns the category in [categories] whose id is [id], or the default
/// category when none matches — e.g. a block still tagged with a category
/// that has since been deleted.
Category categoryById(List<Category> categories, String id) {
  for (final category in categories) {
    if (category.id == id) return category;
  }
  return categories.firstWhere((c) => c.isDefault);
}
