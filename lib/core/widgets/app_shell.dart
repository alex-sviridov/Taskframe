import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/core/widgets/ios_install_hint_banner.dart';

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
          children: _drawerDestinations(),
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
            children: _drawerDestinations(),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: navigationShell),
      ],
    );
  }
}
