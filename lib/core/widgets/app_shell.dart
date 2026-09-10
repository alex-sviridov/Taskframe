import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/responsive.dart';

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
  _Destination(icon: Icons.category, label: 'Categories'),
];

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
          children: _drawerDestinations(),
        ),
        body: Builder(
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
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationDrawer(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: navigationShell.goBranch,
            children: _drawerDestinations(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
