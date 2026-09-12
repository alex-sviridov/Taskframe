import 'package:taskframe/features/category/models/category.dart';

/// A single task: a title, whether it's closed, and an optional category.
/// Unlike a [Category]-tagged schedule block, a task has no time-of-day —
/// it's a flat, unordered-by-time item.
class Task {
  /// Creates a [Task].
  const new({
    required this.id,
    required this.title,
    this.closed = false,
    this.categoryId = Category.defaultId,
  });

  /// Reconstructs a [Task] from a map produced by [toMap].
  factory fromMap(Map<String, Object?> map) => Task(
    id: map['id']! as String,
    title: map['title']! as String,
    closed: map['closed']! as bool,
    categoryId: map['categoryId']! as String,
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

  /// Returns a copy of this task with any of [title]/[closed]/[categoryId]
  /// replaced.
  Task copyWith({String? title, bool? closed, String? categoryId}) => Task(
    id: id,
    title: title ?? this.title,
    closed: closed ?? this.closed,
    categoryId: categoryId ?? this.categoryId,
  );

  /// This task's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'closed': closed,
    'categoryId': categoryId,
  };
}
