import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/category/data/category_repository.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A [CategoryRepository] backed by a sembast [Database], persisting
/// categories across restarts. Records are keyed by [Category.id]; an
/// `order` field (set once at creation, preserved on update) keeps the
/// default category first and the rest in creation order.
///
/// The default category is expected to already exist — written by
/// first-run seeding — but [load] synthesizes one in memory if it's ever
/// missing, so callers always get it first regardless.
class SembastCategoryRepository implements CategoryRepository {
  /// Creates a [SembastCategoryRepository] reading/writing [_db].
  new(this._db);

  final Database _db;

  static final _fallbackDefault = Category(
    id: Category.defaultId,
    name: 'Default',
    colorValue: 0xFF009688,
  );

  @override
  Future<List<Category>> load() async {
    final finder = Finder(
      filter: Filter.notEquals('deleted', true),
      sortOrders: [SortOrder('order')],
    );
    final records = await categoriesStore.find(_db, finder: finder);
    final categories = [
      for (final record in records) Category.fromMap(record.value),
    ];
    if (categories.any((c) => c.isDefault)) return categories;
    return [_fallbackDefault, ...categories];
  }

  @override
  Future<Category> add({
    required String name,
    required int colorValue,
    String? emoji,
  }) async {
    final category = Category(
      id: _uuid.v4(),
      name: name,
      colorValue: colorValue,
      emoji: emoji,
      updatedAt: DateTime.now().toUtc(),
    );
    await categoriesStore.record(category.id).put(_db, {
      ...category.toMap(),
      'order': DateTime.now().microsecondsSinceEpoch,
    });
    return category;
  }

  @override
  Future<Category> update(
    Category category, {
    String? name,
    int? colorValue,
    String? emoji,
  }) async {
    final existingRecord = await categoriesStore.record(category.id).get(_db);
    final current = existingRecord == null
        ? category
        : Category.fromMap(existingRecord);
    final updated = (current.isDefault
            ? current.copyWith(colorValue: colorValue)
            : current.copyWith(
                name: name,
                colorValue: colorValue,
                emoji: emoji,
              ))
        .copyWith(updatedAt: DateTime.now().toUtc());
    final order =
        existingRecord?['order'] ??
        (current.isDefault ? 0 : DateTime.now().microsecondsSinceEpoch);
    await categoriesStore.record(updated.id).put(_db, {
      ...updated.toMap(),
      'order': order,
    });
    return updated;
  }

  @override
  Future<void> delete(Category category) async {
    if (category.isDefault) return;
    final existingRecord = await categoriesStore.record(category.id).get(_db);
    final current = existingRecord == null
        ? category
        : Category.fromMap(existingRecord);
    final tombstone = current.copyWith(
      deleted: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await categoriesStore.record(category.id).put(_db, {
      ...tombstone.toMap(),
      'order': existingRecord?['order'] ?? 0,
    });
  }
}
