import 'package:flutter/material.dart';

/// One row of a [TitleSuggestionsController]'s floating dropdown: [label]
/// shown next to [icon], calling [onSelect] when tapped.
class TitleSuggestionRow {
  /// Creates a [TitleSuggestionRow].
  const new({required this.label, required this.icon, required this.onSelect});

  /// The row's display text.
  final String label;

  /// The row's leading icon.
  final IconData icon;

  /// Called when the row is tapped.
  final VoidCallback onSelect;
}

/// Manages a floating suggestions dropdown anchored to a text field's
/// current position/size, inserted into the ambient [Overlay] on demand —
/// shared by any modal that offers autocomplete for an in-progress token
/// typed into a title field (e.g. `#tag`/`@category`).
///
/// Usage: wrap the text field in `CompositedTransformTarget(link: link,
/// child: Container(key: fieldBoxKey, child: TextField(...)))`, then call
/// [sync] with the current rows (or `null`/empty to hide) from a
/// post-frame callback in `build()`, so the field's render box is
/// guaranteed laid out first. Call [dispose] from the owning state's own
/// `dispose()`.
class TitleSuggestionsController {
  /// Anchors the dropdown to the text field's current position.
  final LayerLink link = LayerLink();

  /// Reads the text field's laid-out size, so the dropdown can match its
  /// width and sit directly below it.
  final GlobalKey fieldBoxKey = GlobalKey();

  OverlayEntry? _entry;
  List<TitleSuggestionRow>? _rows;

  /// Inserts, rebuilds, or removes the floating dropdown to match [rows]
  /// (`null` or empty hides it).
  void sync(BuildContext context, List<TitleSuggestionRow>? rows) {
    _rows = rows;
    if (rows == null || rows.isEmpty) {
      _entry?.remove();
      _entry?.dispose();
      _entry = null;
      return;
    }
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final entry = OverlayEntry(builder: _build);
    _entry = entry;
    Overlay.of(context).insert(entry);
  }

  Widget _build(BuildContext context) {
    final rows = _rows;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();
    final fieldBox =
        fieldBoxKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldSize = fieldBox?.size ?? const Size(300, 48);
    return Positioned(
      width: fieldSize.width,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        offset: Offset(0, fieldSize.height + 4),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in rows)
                  GestureDetector(
                    onTapDown: (_) => row.onSelect(),
                    child: ListTile(
                      dense: true,
                      leading: Icon(row.icon),
                      title: Text(row.label),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Removes the dropdown from the [Overlay], if inserted.
  void dispose() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}
