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
