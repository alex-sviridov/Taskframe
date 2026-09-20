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
    this.activeFrom,
    this.repeat,
    DateTime? updatedAt,
    this.closedAt,
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
    activeFrom: map['activeFrom'] == null
        ? null
        : DateTime.parse(map['activeFrom']! as String),
    repeat: map['repeat'] as String?,
    updatedAt: map['updatedAt'] == null
        ? null
        : DateTime.parse(map['updatedAt']! as String),
    closedAt: map['closedAt'] != null
        ? DateTime.parse(map['closedAt']! as String)
        : (map['closed']! as bool && map['updatedAt'] != null
              ? DateTime.parse(map['updatedAt']! as String)
              : null),
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

  /// The date this task becomes active, or `null` if it always has been.
  /// A task with a future [activeFrom] is not yet active.
  final DateTime? activeFrom;

  /// How often this task recurs, as a compact `<n><unit>` string (`d`/`w`/
  /// `m`/`y` — days/weeks/months/years, e.g. `"1w"`), or `null` if it
  /// doesn't repeat. Closing a task with this set creates its successor
  /// (see `TaskListNotifier.updateTask`).
  final String? repeat;

  /// When this task was last changed. Defaults to the Unix epoch for
  /// records written before sync existed, so they always lose an
  /// LWW comparison against a genuinely newer edit.
  final DateTime updatedAt;

  /// When this task was closed, or `null` if it's open (or was closed
  /// before this field existed and had no `updatedAt` to backfill from —
  /// see [Task.fromMap]). Set automatically by [copyWith] on an
  /// open->closed transition and cleared on a closed->open one.
  final DateTime? closedAt;

  /// Soft-delete tombstone: `true` once removed, so the deletion can
  /// propagate to other devices instead of being silently resurrected.
  final bool deleted;

  /// Whether [activeFrom] is set and still in the future — the task
  /// isn't active yet.
  bool get isNotYetActive =>
      activeFrom != null && activeFrom!.isAfter(DateTime.now());

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Returns a copy of this task with any of [title]/[closed]/[categoryId]/
  /// [tags]/[activeFrom]/[repeat]/[updatedAt]/[deleted] replaced.
  /// [activeFrom]/[repeat] are left unchanged when omitted; pass
  /// [clearActiveFrom]/[clearRepeat] to remove them instead, since `null`
  /// here already means "don't change". [closedAt] is managed
  /// automatically from [closed]'s transition (see [closedAt]'s doc) and
  /// isn't settable directly.
  Task copyWith({
    String? title,
    bool? closed,
    String? categoryId,
    List<String>? tags,
    DateTime? activeFrom,
    bool clearActiveFrom = false,
    String? repeat,
    bool clearRepeat = false,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    final DateTime? closedAt;
    if (closed == null || closed == this.closed) {
      closedAt = this.closedAt;
    } else if (closed) {
      closedAt = DateTime.now();
    } else {
      closedAt = null;
    }
    return Task(
      id: id,
      title: title ?? this.title,
      closed: closed ?? this.closed,
      categoryId: categoryId ?? this.categoryId,
      tags: tags ?? this.tags,
      activeFrom: clearActiveFrom ? null : (activeFrom ?? this.activeFrom),
      repeat: clearRepeat ? null : (repeat ?? this.repeat),
      updatedAt: updatedAt ?? this.updatedAt,
      closedAt: closedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  /// This task's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'closed': closed,
    'categoryId': categoryId,
    'tags': tags,
    'activeFrom': activeFrom?.toIso8601String(),
    'repeat': repeat,
    'updatedAt': updatedAt.toIso8601String(),
    'closedAt': closedAt?.toIso8601String(),
    'deleted': deleted,
  };
}
