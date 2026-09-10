# Adaptive navigation shell

## Purpose

The app currently has two screens (`DayScreen` at `/`, `CategoriesScreen`
at `/categories`) reachable only by direct navigation — there is no nav
chrome at all, and no way to get to `/categories` from within the running
app. This adds a navigation shell wrapping both screens: a bottom
`NavigationBar` on narrow (mobile) widths, a side `NavigationRail` on wide
(desktop) widths, following the same responsive pattern the app already
uses for its modals.

## Scope

In scope:
- A shared responsive-breakpoint constant, replacing the three private
  copies of `_narrowBreakpoint = 700.0` currently duplicated across
  `block_edit_modal.dart`, `category_edit_sheet.dart`, and
  `categories_screen.dart`
- An `AppShell` widget switching between `NavigationBar` (narrow) and
  `NavigationRail` (wide) at that breakpoint
- Restructuring `lib/router.dart` to wrap the existing two routes in a
  `StatefulShellRoute.indexedStack` with two branches, so each
  destination's state (e.g. `DayScreen`'s current page) is preserved when
  switching away and back
- Widget tests for `AppShell` at both widths, and a router-level
  integration test

Out of scope:
- Any new destinations beyond Day/Week and Categories — more branches are
  added later, following this same pattern, as new pages are built
- Any change to `DayScreen` or `CategoriesScreen` internals
- `flutter_adaptive_scaffold` or any other adaptive-layout package — it
  was considered and rejected (see Decisions below)

## Decisions

- **No adaptive-layout package.** `flutter_adaptive_scaffold`
  (`pub.dev/packages/flutter_adaptive_scaffold`) was the initial pick but
  is confirmed discontinued (`isDiscontinued: true` via the pub.dev API,
  no `replacedBy` listed) with no actively maintained alternative found.
  The shell is hand-rolled from `NavigationBar` and `NavigationRail`,
  which are standard Flutter SDK Material widgets, not third-party code.
- **Breakpoint: 700px, matching the app's existing modal breakpoint**
  (`_narrowBreakpoint` in `block_edit_modal.dart` and
  `category_edit_sheet.dart`), not the 900px breakpoint `day_screen.dart`
  uses for its own day-vs-week content switch. These are two independent
  concerns (nav chrome vs. main-panel content) that happen to already use
  different thresholds; the shell adopts the nav-relevant one.
- **State preservation via `StatefulShellRoute.indexedStack`**, not a
  plain `ShellRoute`. Each branch's widget tree (including `DayScreen`'s
  `PageView` position) stays alive in an `IndexedStack` while another
  branch is shown, so switching to Categories and back doesn't reset
  Day/Week's current page.

## Shared breakpoint

New file `lib/core/responsive.dart`:

```dart
/// Below this viewport width, the app shows narrow (mobile) layouts —
/// bottom nav instead of a side rail, near-fullscreen modals instead of
/// centered dialogs, full-bleed lists instead of capped/centered ones.
const narrowBreakpoint = 700.0;

/// Whether [context]'s viewport is narrower than [narrowBreakpoint].
bool isNarrow(BuildContext context) =>
    MediaQuery.sizeOf(context).width < narrowBreakpoint;
```

`block_edit_modal.dart`, `category_edit_sheet.dart`, and
`categories_screen.dart` each drop their private `const _narrowBreakpoint
= 700.0;` and the local `MediaQuery.sizeOf(context).width < _narrowBreakpoint`
checks, importing `isNarrow`/`narrowBreakpoint` from this file instead.
Behavior is unchanged — this is a pure extraction.

## Router

`lib/router.dart` becomes:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/widgets/app_shell.dart';
import 'package:taskframe/features/category/widgets/categories_screen.dart';
import 'package:taskframe/features/day/day_screen.dart';

/// Application router: a shell with two branches (Day/Week, Categories),
/// each keeping its own state alive when the other is shown.
final GoRouter appRouter = GoRouter(
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const DayScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/categories',
              builder: (context, state) => const CategoriesScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
```

`DayScreen` and `CategoriesScreen` themselves are unchanged — each still
owns its own `Scaffold` with its own `AppBar`, exactly as today. The shell
adds chrome *around* them (the bottom bar or side rail); it does not
replace their existing app bars.

## AppShell

New file `lib/core/widgets/app_shell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/responsive.dart';

class _Destination {
  const _Destination({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

const _destinations = [
  _Destination(icon: Icons.calendar_today, label: 'Day'),
  _Destination(icon: Icons.category, label: 'Categories'),
];

/// Wraps [navigationShell] with a bottom [NavigationBar] on narrow
/// widths or a side [NavigationRail] on wide ones, switching at
/// [narrowBreakpoint].
class AppShell extends StatelessWidget {
  const new({required this.navigationShell, super.key});

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
```

`navigationShell.goBranch` matches `NavigationBar.onDestinationSelected`'s
and `NavigationRail.onDestinationSelected`'s `void Function(int)`
signature directly.

## Testing

`test/widget/app_shell_test.dart`: pump `AppShell` inside a real
`MaterialApp.router` (using a small local `GoRouter` with two dummy
branches, so `navigationShell.goBranch` has somewhere to go) at a narrow
width (e.g. 500) and assert a `NavigationBar` with both destination labels
renders and that tapping "Categories" switches the visible branch; repeat
at a wide width (e.g. 1000) asserting a `NavigationRail` instead.

`test/widget/router_test.dart`: pump the real `appRouter` via
`MaterialApp.router(routerConfig: appRouter)`, assert `/` shows
`DayScreen`'s content with the shell's Day destination selected, navigate
(`goBranch` via tapping the Categories destination, or `context.go`) to
`/categories`, and assert `CategoriesScreen`'s content shows with
Categories selected.

Existing `test/widget/day_screen_test.dart` and
`test/widget/categories_screen_test.dart` are unchanged — they pump each
screen directly (`MaterialApp(home: DayScreen())` /
`MaterialApp(home: CategoriesScreen())`), independent of the shell or
router.
