import 'package:flutter/material.dart';

/// One top-level row of the app's sidebar/drawer navigation (a branch
/// destination, or the account entry below the divider).
///
/// Selection is shown with a left accent bar flush to the sidebar's outer
/// edge plus a soft tint — rather than [NavigationDrawerDestination]'s
/// full-width rounded "pill" — so it reads like a persistent sidebar
/// (Linear/Notion/VS Code style) instead of a stock Material drawer.
class SidebarDestinationRow extends StatelessWidget {
  /// Creates a [SidebarDestinationRow].
  const new({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// The row's leading icon.
  final IconData icon;

  /// The row's label text.
  final String label;

  /// Whether this row is the currently active destination.
  final bool selected;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  static const _accentWidth = 3.0;
  static const _shape = BorderRadius.only(
    topRight: Radius.circular(20),
    bottomRight: Radius.circular(20),
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 2),
      child: Stack(
        children: [
          if (selected)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _accentWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(color: colorScheme.primary),
              ),
            ),
          Material(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: _shape,
            child: InkWell(
              onTap: onTap,
              borderRadius: _shape,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
