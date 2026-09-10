# Adaptive Navigation Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap the app's two screens (`DayScreen`, `CategoriesScreen`) in a navigation shell that shows a bottom `NavigationBar` on narrow widths and a side `NavigationRail` on wide widths, using `go_router`'s `StatefulShellRoute.indexedStack` so each screen's state survives switching away and back.

**Architecture:** A shared `lib/core/responsive.dart` breakpoint constant/helper replaces three private duplicates. A new `AppShell` widget renders the nav chrome around whichever branch `go_router` is currently showing. `lib/router.dart` restructures from two flat `GoRoute`s into one `StatefulShellRoute.indexedStack` with two branches, each wrapping one of the existing (unmodified) screens.

**Tech Stack:** Flutter 3.47, `go_router` ^18.0.1 (already a dependency; no new packages — `flutter_adaptive_scaffold` was considered and rejected as discontinued).

**Spec:** `docs/superpowers/specs/2026-09-10-adaptive-nav-shell-design.md`

## Global Constraints

- No new dependencies — `NavigationBar` and `NavigationRail` are Flutter SDK Material widgets.
- Breakpoint is 700px (`narrowBreakpoint`), matching the app's existing modal breakpoint — not the 900px breakpoint `day_screen.dart` uses for its own day/week content switch.
- `DayScreen` and `CategoriesScreen` are not modified — the shell wraps them, it does not replace their own `Scaffold`/`AppBar`.
- Use `StatefulShellRoute.indexedStack` (not plain `ShellRoute`) so branch state persists across navigation.
- Follow existing code style: no comments except non-obvious WHY; full dartdoc on public members (very_good_analysis lint set enabled); unnamed constructors are declared as `const new({...})` per house convention (see `lib/features/category/widgets/categories_screen.dart:17`).

---

### Task 1: Shared responsive breakpoint

**Files:**
- Create: `lib/core/responsive.dart`
- Test: `test/widget/responsive_test.dart`
- Modify: `lib/features/day/widgets/block_edit_modal.dart:1-8,243-278`
- Modify: `lib/features/category/widgets/category_edit_sheet.dart:1-37`
- Modify: `lib/features/category/widgets/categories_screen.dart:1-11,61-63`

**Interfaces:**
- Produces:
  ```dart
  const narrowBreakpoint = 700.0;
  bool isNarrow(BuildContext context);
  ```
  Later tasks (`AppShell` in Task 2) import `narrowBreakpoint` and/or `isNarrow` from `package:taskframe/core/responsive.dart`.

This task is a pure extraction — no behavior changes. The three modified files currently each declare their own private `const _narrowBreakpoint = 700.0;` and compute narrowness locally; after this task they import the shared constant/helper instead. `categories_screen.dart` compares `LayoutBuilder`'s `constraints.maxWidth` (the actual available body width, not the full window) against `narrowBreakpoint` directly — this is intentionally different from the other two files, which check the full viewport width via `isNarrow(context)`, because `categories_screen.dart`'s breakpoint decision is about its own available layout space, not the window.

- [ ] **Step 1: Write the failing test**

Create `test/widget/responsive_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/responsive.dart';

void _setViewportWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('isNarrow', () {
    testWidgets('is true below narrowBreakpoint', (tester) async {
      _setViewportWidth(tester, 600);

      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = isNarrow(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result, isTrue);
    });

    testWidgets('is false at narrowBreakpoint', (tester) async {
      _setViewportWidth(tester, narrowBreakpoint);

      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = isNarrow(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result, isFalse);
    });

    testWidgets('is false above narrowBreakpoint', (tester) async {
      _setViewportWidth(tester, 1000);

      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = isNarrow(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/responsive_test.dart`
Expected: FAIL — `lib/core/responsive.dart` doesn't exist yet.

- [ ] **Step 3: Create the shared breakpoint file**

Create `lib/core/responsive.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Below this viewport width, the app shows narrow (mobile) layouts —
/// bottom nav instead of a side rail, near-fullscreen modals instead of
/// centered dialogs, full-bleed lists instead of capped/centered ones.
const narrowBreakpoint = 700.0;

/// Whether [context]'s viewport is narrower than [narrowBreakpoint].
bool isNarrow(BuildContext context) =>
    MediaQuery.sizeOf(context).width < narrowBreakpoint;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/responsive_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Update `block_edit_modal.dart` to use the shared helper**

In `lib/features/day/widgets/block_edit_modal.dart`, change the import block (currently lines 1-8) from:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
```

to:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
```

Then change (currently lines 243-278):

```dart
/// Below this viewport width, [showBlockEditModal] shows a near-fullscreen
/// bottom sheet; at or above it, a centered fixed-width dialog.
const _narrowBreakpoint = 700.0;

/// Opens the block edit modal for [block] (which belongs to [date]):
/// title, start/end, copy-to-next-day and delete. Near-fullscreen on a
/// narrow (mobile) width, a centered fixed-width dialog on a wide one.
Future<void> showBlockEditModal({
  required BuildContext context,
  required DateTime date,
  required TimeObject block,
}) {
  final isNarrow = MediaQuery.sizeOf(context).width < _narrowBreakpoint;
  if (isNarrow) {
    return showModalBottomSheet<void>(
```

to:

```dart
/// Opens the block edit modal for [block] (which belongs to [date]):
/// title, start/end, copy-to-next-day and delete. Near-fullscreen on a
/// narrow (mobile) width, a centered fixed-width dialog on a wide one.
Future<void> showBlockEditModal({
  required BuildContext context,
  required DateTime date,
  required TimeObject block,
}) {
  if (isNarrow(context)) {
    return showModalBottomSheet<void>(
```

(The rest of the function — the `showModalBottomSheet` and `showDialog` bodies — is unchanged.)

- [ ] **Step 6: Update `category_edit_sheet.dart` to use the shared helper**

In `lib/features/category/widgets/category_edit_sheet.dart`, change the import block (currently lines 1-6) from:

```dart
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
```

to:

```dart
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
```

Then change (currently lines 8-21):

```dart
/// Below this viewport width, [showCategoryEditSheet] shows a
/// near-fullscreen bottom sheet; at or above it, a centered fixed-width
/// dialog. Matches the day feature's block edit modal breakpoint.
const _narrowBreakpoint = 700.0;

/// Opens the edit sheet for [category] (edit mode) or, when [category] is
/// `null`, for creating a new category (create mode). Near-fullscreen on a
/// narrow (mobile) width, a centered fixed-width dialog on a wide one.
Future<void> showCategoryEditSheet({
  required BuildContext context,
  Category? category,
}) {
  final isNarrow = MediaQuery.sizeOf(context).width < _narrowBreakpoint;
  if (isNarrow) {
    return showModalBottomSheet<void>(
```

to:

```dart
/// Opens the edit sheet for [category] (edit mode) or, when [category] is
/// `null`, for creating a new category (create mode). Near-fullscreen on a
/// narrow (mobile) width, a centered fixed-width dialog on a wide one.
Future<void> showCategoryEditSheet({
  required BuildContext context,
  Category? category,
}) {
  if (isNarrow(context)) {
    return showModalBottomSheet<void>(
```

(The rest of the function is unchanged.)

- [ ] **Step 7: Update `categories_screen.dart` to use the shared constant**

In `lib/features/category/widgets/categories_screen.dart`, change the import block (currently lines 1-5) from:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_edit_sheet.dart';
```

to:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_edit_sheet.dart';
```

Then delete the private constant (currently lines 7-11):

```dart
/// Below this viewport width, the category list fills the screen edge to
/// edge (the native mobile list look); at or above it, it's capped and
/// wrapped in a visible card so it doesn't float as bare text in a wide
/// page. Matches the edit sheet's own breakpoint.
const _narrowBreakpoint = 700.0;

```

(delete this whole block, including the trailing blank line), and change the one use site (currently line 63):

```dart
            final isNarrow = constraints.maxWidth < _narrowBreakpoint;
```

to:

```dart
            final isNarrow = constraints.maxWidth < narrowBreakpoint;
```

- [ ] **Step 8: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests — 243 including the 3 new ones — no behavior change to existing screens)

- [ ] **Step 9: Run analyze**

Run: `flutter analyze`
Expected: No new errors or warnings.

- [ ] **Step 10: Commit**

```bash
git add lib/core/responsive.dart test/widget/responsive_test.dart \
  lib/features/day/widgets/block_edit_modal.dart \
  lib/features/category/widgets/category_edit_sheet.dart \
  lib/features/category/widgets/categories_screen.dart
git commit -m "Extract shared responsive breakpoint"
```

---

### Task 2: AppShell widget

**Files:**
- Create: `lib/core/widgets/app_shell.dart`
- Test: `test/widget/app_shell_test.dart`

**Interfaces:**
- Consumes: `narrowBreakpoint`, `isNarrow` from Task 1 (`package:taskframe/core/responsive.dart`); `StatefulNavigationShell` from `package:go_router/go_router.dart` (has `currentIndex` (`int`) and `goBranch(int index, {bool initialLocation})`, tear-off compatible with `void Function(int)`).
- Produces:
  ```dart
  class AppShell extends StatelessWidget {
    const new({required this.navigationShell, super.key});
    final StatefulNavigationShell navigationShell;
  }
  ```
  Task 3's router passes a live `StatefulNavigationShell` to this widget's `navigationShell` parameter.

- [ ] **Step 1: Write the failing test**

Create `test/widget/app_shell_test.dart`. This test builds a small local two-branch router (not the real `appRouter`, which Task 3 builds) so `AppShell` can be tested against `StatefulNavigationShell` in isolation:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/widgets/app_shell.dart';

void _setViewportWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final _testRouter = GoRouter(
  initialLocation: '/one',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/one',
              builder: (context, state) => const Text('Branch one'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/two',
              builder: (context, state) => const Text('Branch two'),
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  group('AppShell', () {
    testWidgets('narrow: shows a NavigationBar with both destinations', (
      tester,
    ) async {
      _setViewportWidth(tester, 600);

      await tester.pumpWidget(MaterialApp.router(routerConfig: _testRouter));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Branch one'), findsOneWidget);
    });

    testWidgets('narrow: tapping the second destination switches branch', (
      tester,
    ) async {
      _setViewportWidth(tester, 600);
      await tester.pumpWidget(MaterialApp.router(routerConfig: _testRouter));

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();

      expect(find.text('Branch two'), findsOneWidget);
      expect(find.text('Branch one'), findsNothing);
    });

    testWidgets('wide: shows a NavigationRail with both destinations', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);

      await tester.pumpWidget(MaterialApp.router(routerConfig: _testRouter));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Branch one'), findsOneWidget);
    });

    testWidgets('wide: tapping the second destination switches branch', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);
      await tester.pumpWidget(MaterialApp.router(routerConfig: _testRouter));

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();

      expect(find.text('Branch two'), findsOneWidget);
      expect(find.text('Branch one'), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/app_shell_test.dart`
Expected: FAIL — `lib/core/widgets/app_shell.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `lib/core/widgets/app_shell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/responsive.dart';

/// One destination in the app's top-level navigation.
class _Destination {
  const _Destination({required this.icon, required this.label});

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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/app_shell_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Run analyze**

Run: `flutter analyze`
Expected: No new errors.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/app_shell.dart test/widget/app_shell_test.dart
git commit -m "Add AppShell (NavigationBar/NavigationRail)"
```

---

### Task 3: Wire the shell into the router

**Files:**
- Modify: `lib/router.dart`
- Test: `test/widget/router_test.dart`

**Interfaces:**
- Consumes: `AppShell` from Task 2 (`package:taskframe/core/widgets/app_shell.dart`); the existing `DayScreen` (`package:taskframe/features/day/day_screen.dart`) and `CategoriesScreen` (`package:taskframe/features/category/widgets/categories_screen.dart`), both unmodified.
- Produces: the restructured `appRouter` (`GoRouter`), same name and type as before — `lib/app.dart` (`MaterialApp.router(routerConfig: appRouter, ...)`) needs no changes.

- [ ] **Step 1: Write the failing test**

Create `test/widget/router_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/widgets/app_shell.dart';
import 'package:taskframe/router.dart';

void main() {
  group('appRouter', () {
    testWidgets('/ shows DayScreen inside the shell with Day selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pump();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.text('Day Frame'), findsOneWidget);
      final shell = tester.widget<AppShell>(find.byType(AppShell));
      expect(shell.navigationShell.currentIndex, 0);
    });

    testWidgets('tapping Categories navigates to /categories', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsWidgets);
      expect(find.text('Default'), findsOneWidget);
      final shell = tester.widget<AppShell>(find.byType(AppShell));
      expect(shell.navigationShell.currentIndex, 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/router_test.dart`
Expected: FAIL — `appRouter` still uses flat `GoRoute`s with no `AppShell`, so `find.byType(AppShell)` finds nothing.

- [ ] **Step 3: Restructure the router**

Replace the full contents of `lib/router.dart` with:

```dart
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

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/router_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests, including `test/widget/day_screen_test.dart` and `test/widget/categories_screen_test.dart`, which pump `DayScreen`/`CategoriesScreen` directly and are unaffected by the router change)

- [ ] **Step 6: Run analyze**

Run: `flutter analyze`
Expected: No new errors.

- [ ] **Step 7: Commit**

```bash
git add lib/router.dart test/widget/router_test.dart
git commit -m "Wire AppShell into the router via StatefulShellRoute"
```

---

## Self-Review Notes

- **Spec coverage:** shared breakpoint extraction (Task 1) covers the "Shared breakpoint" spec section and the three call-site updates listed under Scope; `AppShell` (Task 2) covers the "AppShell" spec section including the shared destinations list and both `NavigationBar`/`NavigationRail` renderings; router restructuring (Task 3) covers the "Router" spec section, including that `DayScreen`/`CategoriesScreen` stay unmodified. The `Decisions` section (no `flutter_adaptive_scaffold`, 700px breakpoint, `indexedStack` for state preservation) is reflected in the Global Constraints and Tech Stack. The "Testing" spec section's three test files are exactly Tasks 1–3's test files.
- **Type consistency:** `StatefulNavigationShell` and its `currentIndex`/`goBranch` are used identically in Task 2's `AppShell` and Task 3's router/tests. `narrowBreakpoint`/`isNarrow` from Task 1 are the only symbols Task 2's `AppShell` and Task 3's test import from `core/responsive.dart` — no renamed or redefined variants anywhere.
- **No placeholders:** every step's code is complete and runnable; the before/after diffs in Task 1 quote exact current file contents (verified against the live files while writing this plan) so an implementer isn't guessing at surrounding context.
