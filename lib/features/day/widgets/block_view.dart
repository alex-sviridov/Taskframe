import 'package:flutter/material.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// Renders a single [TimeObject] on the day grid.
///
/// An [BlockKind.anchor] is filled; a [BlockKind.frame] is only outlined,
/// since it marks where attention goes rather than a concrete activity.
class BlockView extends StatelessWidget {
  /// Creates a [BlockView] for [block].
  const new({required this.block, super.key});

  /// The block to render.
  final TimeObject block;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAnchor = block.kind == BlockKind.anchor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isAnchor ? scheme.primaryContainer : null,
        border: isAnchor ? null : Border.all(color: scheme.primary),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        block.title,
        style: Theme.of(context).textTheme.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
