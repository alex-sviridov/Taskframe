import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/responsive.dart';

/// One destination in the app's top-level navigation.
class _Destination {
  const new({required this.icon, required this.label});

  /// The destination's icon, shown in both the bottom bar and the rail.
  final IconData icon;

  /// The destination's label, shown in both the bottom bar and the rail.
  final String label;
}

/// The app's top-level destinations, in branch order. Shared between the
/// [NavigationBar] and [NavigationRail] renderings so they never drift out
/// of sync with each other.
const _destinations = [
  _Destination(icon: Icons.calendar_today, label: 'Day'),
  _Destination(icon: Icons.category, label: 'Categories'),
];

/// Wraps [navigationShell] with a bottom [NavigationBar] on narrow widths
/// or a side [NavigationRail] on wide ones, switching at [narrowBreakpoint].
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
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: navigationShell.goBranch,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon), label: d.label),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: navigationShell.goBranch,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
