import 'package:flutter/material.dart';

/// Picks black or white — whichever reads legibly — for text/icons drawn
/// on top of [background]. Used by [ColoredListCard] itself, and
/// reusable anywhere else that needs to dim/style text against an
/// arbitrary, user-chosen category color rather than a fixed theme color
/// (a fixed color can't guarantee contrast against every possible
/// category color).
Color foregroundColorFor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black;

/// A rounded, filled list row used for both `TaskCard` and category list
/// rows: a colored `Container` (the row's own color, e.g. a task's or
/// category's category color) wrapping a `ListTile`, so tapping anywhere
/// on the row responds with the usual ink feedback.
class ColoredListCard extends StatelessWidget {
  /// Creates a [ColoredListCard] filled with [color].
  const new({
    required this.color,
    required this.title,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  /// The row's background color.
  final Color color;

  /// The `ListTile.title`.
  final Widget title;

  /// The `ListTile.leading`, if any.
  final Widget? leading;

  /// The `ListTile.trailing`, if any.
  final Widget? trailing;

  /// Called when the row is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = foregroundColorFor(color);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTileTheme.merge(
          textColor: foreground,
          iconColor: foreground,
          child: ListTile(
            leading: leading,
            title: title,
            trailing: trailing,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
