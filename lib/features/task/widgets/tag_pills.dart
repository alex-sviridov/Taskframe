import 'package:flutter/material.dart';

/// Renders [tags] as pills under a task's title. When [onRemoved] is
/// given, each pill shows a delete icon that calls it with the removed
/// tag — used in the edit modal. Renders nothing when [tags] is empty.
class TagPills extends StatelessWidget {
  /// Creates a [TagPills] for [tags]. Pass [onRemoved] to make pills
  /// removable (edit mode); omit it for read-only display (the task
  /// card).
  const new({required this.tags, super.key, this.onRemoved});

  /// The tags to render as pills, in order.
  final List<String> tags;

  /// Called with a tag when its pill's delete icon is tapped. `null`
  /// renders read-only pills with no delete icon.
  final ValueChanged<String>? onRemoved;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final tag in tags)
          if (onRemoved == null)
            Chip(
              label: Text(tag),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          else
            InputChip(label: Text(tag), onDeleted: () => onRemoved!(tag)),
      ],
    );
  }
}
