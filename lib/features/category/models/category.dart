/// A category blocks can be tagged with (application to blocks is out of
/// scope for this model — it exists purely for the category management
/// view).
class Category {
  /// Creates a [Category].
  const new({
    required this.id,
    required this.name,
    required this.colorValue,
    this.emoji,
  });

  /// The id of the single, permanent default category. Identifying it by
  /// this constant (rather than a separate boolean flag) keeps "is this
  /// the default" a single source of truth.
  static const String defaultId = '0';

  /// Unique identifier for this category.
  final String id;

  /// Display name. Fixed for the default category.
  final String name;

  /// The category's color, as an ARGB32 value (e.g. `Color.toARGB32()`).
  final int colorValue;

  /// The category's emoji, or `null` for the default category, which has
  /// none.
  final String? emoji;

  /// Whether this is the single, permanent default category.
  bool get isDefault => id == defaultId;

  /// [title] prefixed with this category's emoji, or [title] unchanged
  /// when it has none.
  String formatTitle(String title) => emoji == null ? title : '$emoji $title';

  /// Returns a copy of this category with any of [name]/[colorValue]/
  /// [emoji] replaced.
  Category copyWith({String? name, int? colorValue, String? emoji}) => Category(
    id: id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    emoji: emoji ?? this.emoji,
  );
}
