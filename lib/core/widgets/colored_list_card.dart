import 'package:flutter/material.dart';

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
    // Picks black or white text/icons based on the row's own background,
    // so an arbitrarily-chosen category color (e.g. a light yellow) never
    // ends up rendering light text on a light background.
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
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
