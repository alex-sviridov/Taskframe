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
  /// ReorderableListView's onReorder (i.e. [newIndex] is the index in the
  /// list *before* the moved item is removed) — persisting the new order
  /// via the repository and refreshing state.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final repository = ref.read(savedSearchRepositoryProvider);
    final current = [...?state.value];
    var adjustedNewIndex = newIndex;
    if (adjustedNewIndex > oldIndex) adjustedNewIndex -= 1;
    final moved = current.removeAt(oldIndex);
    current.insert(adjustedNewIndex, moved);
    state = AsyncData(current);
    await repository.reorder(current);
  }
}

/// The list of saved search views, in sidebar order.
final savedSearchListProvider =
    AsyncNotifierProvider<SavedSearchListNotifier, List<SavedSearch>>(
      SavedSearchListNotifier.new,
    );
