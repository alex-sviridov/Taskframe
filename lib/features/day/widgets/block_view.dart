import 'package:flutter/material.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// Renders a single [TimeObject] on the day grid.
///
/// An [BlockKind.anchor] is filled; a [BlockKind.frame] is only outlined,
/// since it marks where attention goes rather than a concrete activity.
/// Filled/outlined with [category]'s color when given, falling back to the
/// theme's own colors while categories are still loading.
class BlockView extends StatelessWidget {
  /// Creates a [BlockView] for [block].
  const new({
    required this.block,
    this.showTitle = true,
    this.category,
    super.key,
  });

  /// The block to render.
  final TimeObject block;

  /// Whether to draw the title inside this box. `false` for the main day
  /// grid, whose own title-overlay layer draws every title on top of all
  /// blocks instead (see `DayGrid`), so a short block's title is never
  /// covered by a neighbor's box painted after it.
  final bool showTitle;

  /// The category [block] is tagged with, or `null` while categories are
  /// still loading. Supplies the paint color and, when it has an emoji,
  /// the emoji prefixed onto the shown title.
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAnchor = block.kind == BlockKind.anchor;
    final categoryColor = category == null ? null : Color(category!.colorValue);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isAnchor ? (categoryColor ?? scheme.primaryContainer) : null,
        border: isAnchor
            ? null
            : Border.all(color: categoryColor ?? scheme.primary),
        borderRadius: BorderRadius.circular(4),
      ),
      child: showTitle
          ? Text(
              category?.formatTitle(block.title) ?? block.title,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            )
          : null,
    );
  }
}
