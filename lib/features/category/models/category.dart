/// A category blocks can be tagged with (application to blocks is out of
/// scope for this model — it exists purely for the category management
/// view).
class Category {
  /// Creates a [Category].
  new({
    required this.id,
    required this.name,
    required this.colorValue,
    this.emoji,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? _epoch;

  /// Reconstructs a [Category] from a map produced by [toMap].
  factory fromMap(Map<String, Object?> map) => Category(
    id: map['id']! as String,
    name: map['name']! as String,
    colorValue: map['colorValue']! as int,
    emoji: map['emoji'] as String?,
    updatedAt: map['updatedAt'] == null
        ? _epoch
        : DateTime.parse(map['updatedAt']! as String),
    deleted: map['deleted'] as bool? ?? false,
  );

  /// The id of the single, permanent default category. Identifying it by
  /// this constant (rather than a separate boolean flag) keeps "is this
  /// the default" a single source of truth.
  static const String defaultId = '0';

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Unique identifier for this category.
  final String id;

  /// Display name. Fixed for the default category.
  final String name;

  /// The category's color, as an ARGB32 value (e.g. `Color.toARGB32()`).
  final int colorValue;

  /// The category's emoji, or `null` for the default category, which has
  /// none.
  final String? emoji;

  /// When this category was last changed. Defaults to the Unix epoch for
  /// records written before sync existed, so they always lose an
  /// LWW comparison against a genuinely newer edit.
  final DateTime updatedAt;

  /// Soft-delete tombstone: `true` once removed, so the deletion can
  /// propagate to other devices instead of being silently resurrected.
  final bool deleted;

  /// Whether this is the single, permanent default category.
  bool get isDefault => id == defaultId;

  /// [title] prefixed with this category's emoji, or [title] unchanged
  /// when it has none.
  String formatTitle(String title) => emoji == null ? title : '$emoji $title';

  /// Returns a copy of this category with any of [name]/[colorValue]/
  /// [emoji]/[updatedAt]/[deleted] replaced.
  Category copyWith({
    String? name,
    int? colorValue,
    String? emoji,
    DateTime? updatedAt,
    bool? deleted,
  }) => Category(
    id: id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    emoji: emoji ?? this.emoji,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );

  /// This category's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'emoji': emoji,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
  };
}
