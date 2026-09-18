import 'package:meta/meta.dart';

/// One template: a named, reusable set of events, editable with the same
/// schedule UI a real day uses (see `TemplatesScreen`).
@immutable
class Template {
  /// Creates a [Template].
  new({
    required this.id,
    required this.name,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? _epoch;

  /// Reconstructs a [Template] from a map produced by [toMap].
  factory fromMap(Map<String, Object?> map) => Template(
    id: map['id']! as String,
    name: map['name']! as String,
    updatedAt: map['updatedAt'] == null
        ? _epoch
        : DateTime.parse(map['updatedAt']! as String),
    deleted: map['deleted'] as bool? ?? false,
  );

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Unique identifier for this template — also its `TemplateColumn.
  /// templateId`.
  final String id;

  /// Display name, shown as this template's column header.
  final String name;

  /// When this template was last changed. Defaults to the Unix epoch for
  /// records written before sync existed, so they always lose an
  /// LWW comparison against a genuinely newer edit.
  final DateTime updatedAt;

  /// Whether this template has been soft-deleted. Defaults to `false`.
  final bool deleted;

  /// Returns a copy of this template with [name], [updatedAt], or
  /// [deleted] replaced.
  Template copyWith({String? name, DateTime? updatedAt, bool? deleted}) =>
      Template(
        id: id,
        name: name ?? this.name,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
      );

  /// This template's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
  };

  @override
  bool operator ==(Object other) =>
      other is Template &&
      other.id == id &&
      other.name == name &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(id, name, updatedAt, deleted);
}
