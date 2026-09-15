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

  Category _defaultCategory = Category(
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
      return _defaultCategory = _defaultCategory.copyWith(
        colorValue: colorValue,
      );
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
