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
  Future<SavedSearch> add({required String name, required String query}) async {
    final nextOrder = _views.isEmpty
        ? 0
        : _views.map((v) => v.order).reduce((a, b) => a > b ? a : b) + 1;
    final view = SavedSearch(
      id: 'saved-search-${_nextId++}',
      name: name,
      query: query,
      order: nextOrder,
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
