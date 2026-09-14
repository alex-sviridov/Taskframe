import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/core/widgets/ios_install_hint_banner.dart';
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
  _Destination(icon: Icons.calendar_today, label: 'Day'),
  _Destination(icon: Icons.dashboard_customize, label: 'Templates'),
  _Destination(icon: Icons.category, label: 'Categories'),
  _Destination(icon: Icons.check_circle_outline, label: 'Tasks'),
];

/// Width of the persistent (wide-width) sidebar — 30% narrower than
/// [NavigationDrawer]'s own default width of 304 (304 * 0.7 = 212.8,
/// rounded to a whole pixel: a fractional width here was enough to push
/// layout into an extra pass, which could transiently double-build the
/// day view's paged content underneath).
const _sidebarWidth = 213.0;

List<NavigationDrawerDestination> _drawerDestinations() => [
  for (final d in _destinations)
    NavigationDrawerDestination(icon: Icon(d.icon), label: Text(d.label)),
];

/// Wraps [navigationShell] with navigation to its branches: a hidden
/// [NavigationDrawer] opened by a hamburger button on narrow widths, or a
/// permanently visible [NavigationDrawer] acting as a sidebar on wide ones,
/// switching at [narrowBreakpoint].
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
        drawer: NavigationDrawer(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            Navigator.pop(context);
            navigationShell.goBranch(index);
          },
          children: [
            ..._drawerDestinations(),
            const _SavedViewsSection(isNarrow: true),
          ],
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
        // NavigationDrawer has no width parameter of its own — it always
        // builds a Drawer, whose default width (304) is baked in via a
        // tight BoxConstraints.expand, so shrinking it as a persistent
        // sidebar means constraining it from outside like this rather
        // than passing it any property directly.
        SizedBox(
          width: _sidebarWidth,
          child: NavigationDrawer(
            // The narrower sidebar no longer has room for the default
            // tile padding (24px total) without its longest label
            // ("Categories") overflowing.
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: navigationShell.goBranch,
            children: [
              ..._drawerDestinations(),
              const _SavedViewsSection(isNarrow: false),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: navigationShell),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 16, 16, 4),
          child: Text(
            'Saved views',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ReorderableListView(
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
              ),
          ],
        ),
      ],
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
    super.key,
  });

  final SavedSearch view;
  final int index;
  final bool isNarrow;

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
    // Applied to both the label and the rename field, so switching between
    // them never changes the text size — ListTile's default title style
    // otherwise diverges from a bare TextField's default style.
    final titleStyle = Theme.of(context).textTheme.bodyLarge;
    final colorScheme = Theme.of(context).colorScheme;

    final row = ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 48, right: 8),
      title: _renaming
          ? TextField(
              controller: _nameController,
              autofocus: true,
              style: titleStyle,
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
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
              onSubmitted: (_) => _submitRename(),
              onTapOutside: (_) => _submitRename(),
            )
          : Text(
              widget.view.name,
              style: titleStyle,
              overflow: TextOverflow.ellipsis,
            ),
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
