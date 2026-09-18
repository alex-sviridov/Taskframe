import 'package:taskframe/features/category/models/category.dart';

/// A single task: a title, whether it's closed, and an optional category.
/// Unlike a [Category]-tagged schedule block, a task has no time-of-day —
/// it's a flat, unordered-by-time item.
class Task {
  /// Creates a [Task].
  new({
    required this.id,
    required this.title,
    this.closed = false,
    this.categoryId = Category.defaultId,
    this.tags = const [],
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? _epoch;

  /// Reconstructs a [Task] from a map produced by [toMap]. `tags` defaults
  /// to empty when absent, so a task persisted before tags existed still
  /// loads.
  factory fromMap(Map<String, Object?> map) => Task(
    id: map['id']! as String,
    title: map['title']! as String,
    closed: map['closed']! as bool,
    categoryId: map['categoryId']! as String,
    tags: [for (final tag in map['tags'] as List? ?? const []) tag as String],
    updatedAt: map['updatedAt'] == null
        ? null
        : DateTime.parse(map['updatedAt']! as String),
    deleted: map['deleted'] as bool? ?? false,
  );

  /// Unique identifier for this task.
  final String id;

  /// The task's title.
  final String title;

  /// Whether this task has been closed (marked done). Defaults to `false`.
  final bool closed;

  /// The id of the [Category] this task is tagged with. Defaults to
  /// [Category.defaultId], so every task always resolves to some category.
  final String categoryId;

  /// Free-form tags attached to this task (lowercase, no `#`), parsed out
  /// of the title as the user types. Defaults to empty.
  final List<String> tags;

  /// When this task was last changed. Defaults to the Unix epoch for
  /// records written before sync existed, so they always lose an
  /// LWW comparison against a genuinely newer edit.
  final DateTime updatedAt;

  /// Soft-delete tombstone: `true` once removed, so the deletion can
  /// propagate to other devices instead of being silently resurrected.
  final bool deleted;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Returns a copy of this task with any of [title]/[closed]/[categoryId]/
  /// [tags]/[updatedAt]/[deleted] replaced.
  Task copyWith({
    String? title,
    bool? closed,
    String? categoryId,
    List<String>? tags,
    DateTime? updatedAt,
    bool? deleted,
  }) => Task(
    id: id,
    title: title ?? this.title,
    closed: closed ?? this.closed,
    categoryId: categoryId ?? this.categoryId,
    tags: tags ?? this.tags,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );

  /// This task's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'closed': closed,
    'categoryId': categoryId,
    'tags': tags,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
  };
}
