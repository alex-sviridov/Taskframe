import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/core/widgets/ios_install_hint_banner.dart';
import 'package:taskframe/core/widgets/sidebar_row.dart';
import 'package:taskframe/core/widgets/sync_status_indicator.dart';
import 'package:taskframe/features/saved_search/models/saved_search.dart';
import 'package:taskframe/features/saved_search/providers.dart';

/// One destination in the app's top-level navigation.
class _Destination {
  const new({required this.icon, required this.label});

  /// The destination's icon, shown in both the drawer and the sidebar.
  final IconData icon;

  /// The destination's label, shown in both the drawer and the sidebar.
  final String label;
}

/// The app's top-level destinations, in branch order. Shared between the
/// narrow (hidden drawer) and wide (persistent sidebar) renderings so they
/// never drift out of sync with each other.
const _destinations = [
  _Destination(icon: Icons.wb_sunny_outlined, label: 'Now'),
  _Destination(icon: Icons.calendar_today, label: 'Day'),
  _Destination(icon: Icons.dashboard_customize, label: 'Templates'),
  _Destination(icon: Icons.category, label: 'Categories'),
  _Destination(icon: Icons.check_circle_outline, label: 'Tasks'),
];

/// Width of the persistent (wide-width) sidebar — 30% narrower than
/// [Drawer]'s own default width of 304 (304 * 0.7 = 212.8, rounded to a
/// whole pixel: a fractional width here was enough to push layout into
/// an extra pass, which could transiently double-build the day view's
/// paged content underneath).
const _sidebarWidth = 213.0;

/// Wraps [navigationShell] with navigation to its branches: a hidden
/// drawer opened by a hamburger button on narrow widths, or a
/// permanently visible sidebar on wide ones, switching at
/// [narrowBreakpoint].
class AppShell extends StatelessWidget {
  /// Creates an [AppShell] around [navigationShell].
  const new({required this.navigationShell, super.key});

  /// The currently active branch and the means to switch between branches,
  /// supplied by go_router's [StatefulShellRoute.indexedStack].
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    if (isNarrow(context)) {
      return Scaffold(
        drawer: Drawer(
          child: SafeArea(
            child: _SidebarContent(
              navigationShell: navigationShell,
              isNarrow: true,
              onDestinationSelected: (index) {
                Navigator.pop(context);
                navigationShell.goBranch(index);
              },
            ),
          ),
        ),
        body: Column(
          children: [
            const SafeArea(bottom: false, child: IosInstallHintBanner()),
            Expanded(
              child: Builder(
                builder: (context) => Stack(
                  children: [
                    navigationShell,
                    Positioned(
                      top: MediaQuery.paddingOf(context).top,
                      left: 4,
                      child: IconButton(
                        tooltip: 'Menu',
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          const SafeArea(bottom: false, child: IosInstallHintBanner()),
          Expanded(child: _wideBody(navigationShell)),
        ],
      ),
    );
  }

  Widget _wideBody(StatefulNavigationShell navigationShell) {
    return Row(
      children: [
        SizedBox(
          key: const ValueKey('wideSidebar'),
          width: _sidebarWidth,
          child: Builder(
            builder: (context) => Material(
              color: Theme.of(context).colorScheme.surface,
              child: _SidebarContent(
                navigationShell: navigationShell,
                isNarrow: false,
                onDestinationSelected: navigationShell.goBranch,
              ),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: navigationShell),
      ],
    );
  }
}

/// The shared content of both the narrow drawer and the wide persistent
/// sidebar: the top-level destinations, the saved-views section, and the
/// account entry below a divider. Kept in one place so the two layouts
/// never drift out of sync with each other.
class _SidebarContent extends StatelessWidget {
  const new({
    required this.navigationShell,
    required this.isNarrow,
    required this.onDestinationSelected,
  });

  final StatefulNavigationShell navigationShell;
  final bool isNarrow;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final currentIndex = navigationShell.currentIndex;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (var i = 0; i < _destinations.length; i++)
          SidebarDestinationRow(
            icon: _destinations[i].icon,
            label: _destinations[i].label,
            selected: currentIndex == i,
            onTap: () => onDestinationSelected(i),
          ),
        _SavedViewsSection(isNarrow: isNarrow),
        const Divider(),
        SidebarDestinationRow(
          icon: Icons.account_circle,
          label: 'Account',
          selected: currentIndex == _destinations.length,
          onTap: () => onDestinationSelected(_destinations.length),
        ),
        const SyncStatusIndicator(),
      ],
    );
  }
}

/// The "Saved views" sidebar section, listed directly under the "Tasks"
/// destination — hidden entirely while there are no saved views.
class _SavedViewsSection extends ConsumerWidget {
  const new({required this.isNarrow});

  /// Whether this is rendered in the narrow (drawer) or wide (persistent
  /// sidebar) layout — controls whether tapping a view also closes the
  /// drawer, and whether row affordances reveal on long-press vs. hover.
  final bool isNarrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views =
        ref.watch(savedSearchListProvider).value ?? const <SavedSearch>[];
    if (views.isEmpty) return const SizedBox.shrink();

    // Reading GoRouterState here (rather than just once from wherever the
    // route was pushed) makes this section rebuild whenever the URL's `q`
    // changes — including when the user edits the search box directly —
    // so the highlighted row always tracks the search bar's current query,
    // not just the view that was last tapped.
    final currentQuery = GoRouterState.of(context).uri.queryParameters['q'];

    // The left border reads as a neutral tree guide rather than a
    // selection accent (that's reserved for the primary-colored bar on
    // selected rows themselves) — offset under the destination icon
    // column, with the section's own content padding (32) picking up the
    // rest of the indent the rows used to carry entirely on their own
    // (48), so text still lands at the same x as before.
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 2,
            ),
          ),
        ),
        child: ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          // onReorderItem pre-adjusts newIndex for the removed item, but
          // SavedSearchListNotifier.reorder already does that adjustment
          // itself; migrating both sides is out of scope for this fix.
          // ignore: deprecated_member_use
          onReorder: (oldIndex, newIndex) => ref
              .read(savedSearchListProvider.notifier)
              .reorder(oldIndex, newIndex),
          children: [
            for (var i = 0; i < views.length; i++)
              _SavedViewRow(
                key: ValueKey(views[i].id),
                view: views[i],
                index: i,
                isNarrow: isNarrow,
                isSelected: views[i].query == currentQuery,
              ),
          ],
        ),
      ),
    );
  }
}

/// One row of [_SavedViewsSection]. Tapping navigates to the view's
/// query. On wide layouts, hovering the row reveals a trailing overflow
/// menu (Rename/Delete); on narrow layouts, long-pressing does. Rename
/// swaps the label for an inline, autofocused text field.
class _SavedViewRow extends ConsumerStatefulWidget {
  const new({
    required this.view,
    required this.index,
    required this.isNarrow,
    required this.isSelected,
    super.key,
  });

  final SavedSearch view;
  final int index;
  final bool isNarrow;

  /// Whether this view's query matches the search bar's current query —
  /// highlighted the same way the selected top-level destination is.
  final bool isSelected;

  @override
  ConsumerState<_SavedViewRow> createState() => _SavedViewRowState();
}

class _SavedViewRowState extends ConsumerState<_SavedViewRow> {
  bool _revealed = false;
  bool _renaming = false;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.view.name);
  }

  @override
  void didUpdateWidget(covariant _SavedViewRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_renaming && oldWidget.view.name != widget.view.name) {
      _nameController.text = widget.view.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _navigate(BuildContext context) {
    if (widget.isNarrow) Navigator.pop(context);
    context.go('/tasks?q=${Uri.encodeQueryComponent(widget.view.query)}');
  }

  void _submitRename() {
    final newName = _nameController.text.trim();
    setState(() {
      _renaming = false;
      _revealed = false;
    });
    if (newName.isEmpty || newName == widget.view.name) {
      _nameController.text = widget.view.name;
      return;
    }
    unawaited(
      ref
          .read(savedSearchListProvider.notifier)
          .renameView(widget.view, newName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final row = ListTile(
      dense: true,
      // The section's own right: 8 padding already insets the tile from
      // the sidebar edge to align with the Tasks pill above, so no
      // additional right content padding is needed here.
      contentPadding: const EdgeInsets.only(left: 32),
      // Left corners stay square so the selected pill continues the
      // straight accent-bar line unbroken instead of curving away from it.
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      selected: widget.isSelected,
      // Same tint language as the top-level [SidebarDestinationRow]
      // rows, rather than a distinct secondaryContainer "chip" style, so
      // selection reads consistently across parent and child rows.
      selectedTileColor: colorScheme.primary.withValues(alpha: 0.08),
      selectedColor: colorScheme.primary,
      title: _renaming
          // Reads DefaultTextStyle from inside the title slot, so the field
          // always matches whatever text style ListTile would otherwise
          // have applied to a plain Text here (a size picked independently
          // — e.g. textTheme.bodyLarge — previously overflowed this narrow,
          // indented row and got ellipsized mid-word).
          ? Builder(
              builder: (context) => TextField(
                controller: _nameController,
                autofocus: true,
                style: DefaultTextStyle.of(context).style,
                cursorColor: colorScheme.primary,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
                onSubmitted: (_) => _submitRename(),
                onTapOutside: (_) => _submitRename(),
              ),
            )
          : Text(widget.view.name, overflow: TextOverflow.ellipsis),
      // While _revealed (hover/long-press, menu not yet opened or open),
      // kept in the tree and only toggled via Opacity/IgnorePointer, never
      // removed — removing the PopupMenuButton from the tree while its menu
      // route is open (which happens the instant the cursor leaves this
      // row's MouseRegion to move onto the menu overlay itself) breaks the
      // open menu's item selection, since the button that owns the route
      // gets disposed mid-interaction. Same pattern as _HoverReveal in
      // apply_template_button.dart. Once _renaming is true, the popup menu
      // that got us here has already closed (selecting "Rename" closes it),
      // so it's then safe to drop trailing entirely and give the rename
      // TextField the full row width.
      trailing: _renaming
          ? null
          : Opacity(
              opacity: _revealed ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_revealed,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReorderableDragStartListener(
                      index: widget.index,
                      child: const Icon(Icons.drag_indicator, size: 18),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      onSelected: (choice) {
                        if (choice == 'rename') {
                          setState(() => _renaming = true);
                        } else if (choice == 'delete') {
                          setState(() => _revealed = false);
                          unawaited(
                            ref
                                .read(savedSearchListProvider.notifier)
                                .deleteView(widget.view),
                          );
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      onTap: _renaming ? null : () => _navigate(context),
      onLongPress: widget.isNarrow
          ? () => setState(() => _revealed = !_revealed)
          : null,
    );

    if (widget.isNarrow) return row;
    return MouseRegion(
      onEnter: (_) => setState(() => _revealed = true),
      onExit: (_) => setState(() => _revealed = false),
      child: row,
    );
  }
}
