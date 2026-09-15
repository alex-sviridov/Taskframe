import 'package:flutter/foundation.dart';

/// A pinned Tasks search query, shown in the sidebar under "Tasks".
@immutable
class SavedSearch {
  /// Creates a [SavedSearch].
  new({
    required this.id,
    required this.name,
    required this.query,
    required this.order,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? _epoch;

  /// Reconstructs a [SavedSearch] from a map produced by [toMap].
  factory fromMap(Map<String, Object?> map) => SavedSearch(
    id: map['id']! as String,
    name: map['name']! as String,
    query: map['query']! as String,
    order: map['order']! as int,
    updatedAt: map['updatedAt'] == null
        ? _epoch
        : DateTime.parse(map['updatedAt']! as String),
    deleted: map['deleted'] as bool? ?? false,
  );

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Unique identifier for this saved view.
  final String id;

  /// User-editable display name, e.g. "Tasks view 2".
  final String name;

  /// The raw search text this view reloads into the Tasks search bar.
  final String query;

  /// Sidebar position — lower sorts first.
  final int order;

  /// When this view was last changed. Defaults to the Unix epoch for
  /// records written before sync existed, so they always lose an
  /// LWW comparison against a genuinely newer edit.
  final DateTime updatedAt;

  /// Soft-delete tombstone: `true` once removed, so the deletion can
  /// propagate to other devices instead of being silently resurrected.
  final bool deleted;

  /// Returns a copy of this view with any of [name]/[query]/[order]/
  /// [updatedAt]/[deleted] replaced.
  SavedSearch copyWith({
    String? name,
    String? query,
    int? order,
    DateTime? updatedAt,
    bool? deleted,
  }) => SavedSearch(
    id: id,
    name: name ?? this.name,
    query: query ?? this.query,
    order: order ?? this.order,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );

  /// This view's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'query': query,
    'order': order,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
  };

  @override
  bool operator ==(Object other) =>
      other is SavedSearch &&
      other.id == id &&
      other.name == name &&
      other.query == query &&
      other.order == order &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(id, name, query, order, updatedAt, deleted);
}
