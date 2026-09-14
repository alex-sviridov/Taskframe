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
