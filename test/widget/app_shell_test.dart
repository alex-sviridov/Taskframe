import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/widgets/app_shell.dart';

void _setViewportWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

GoRouter _buildTestRouter() => GoRouter(
  initialLocation: '/one',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/zero',
              builder: (context, state) => const Text('Branch zero'),
            ),
          ],
        ),
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
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/three',
              builder: (context, state) => const Text('Branch three'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/four',
              builder: (context, state) => const Text('Branch four'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/account',
              builder: (context, state) => const Text('Account screen'),
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  group('AppShell', () {
    testWidgets('narrow: the drawer starts closed, with a menu button', (
      tester,
    ) async {
      _setViewportWidth(tester, 600);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: _buildTestRouter()),
        ),
      );

      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.text('Templates'), findsNothing);
      expect(find.text('Categories'), findsNothing);
      expect(find.text('Branch one'), findsOneWidget);
    });

    testWidgets('narrow: the menu button opens the drawer', (tester) async {
      _setViewportWidth(tester, 600);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: _buildTestRouter()),
        ),
      );

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDrawer), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
    });

    testWidgets(
      'narrow: tapping a destination in the open drawer switches branch',
      (tester) async {
        _setViewportWidth(tester, 600);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(routerConfig: _buildTestRouter()),
          ),
        );

        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Templates'));
        await tester.pumpAndSettle();

        expect(find.text('Branch two'), findsOneWidget);
        expect(find.text('Branch one'), findsNothing);
      },
    );

    testWidgets('wide: shows a persistent sidebar with all destinations', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: _buildTestRouter()),
        ),
      );

      expect(find.byType(NavigationDrawer), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsNothing);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Branch one'), findsOneWidget);
    });

    testWidgets('wide: the persistent sidebar is 30% narrower than the '
        'NavigationDrawer default (304 * 0.7 ≈ 213)', (tester) async {
      _setViewportWidth(tester, 1000);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: _buildTestRouter()),
        ),
      );

      final width = tester.getSize(find.byType(NavigationDrawer)).width;
      expect(width, closeTo(213, 1));
    });

    testWidgets('wide: tapping the second destination switches branch', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: _buildTestRouter()),
        ),
      );

      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();

      expect(find.text('Branch two'), findsOneWidget);
      expect(find.text('Branch one'), findsNothing);
    });

    testWidgets('wide: tapping the third destination switches branch', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: _buildTestRouter()),
        ),
      );

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();

      expect(find.text('Branch three'), findsOneWidget);
      expect(find.text('Branch one'), findsNothing);
    });

    testWidgets('narrow: tapping "Account" in the open drawer navigates to '
        'account', (tester) async {
      _setViewportWidth(tester, 600);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: _buildTestRouter()),
        ),
      );

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();

      expect(find.text('Account screen'), findsOneWidget);
    });

    testWidgets('wide: tapping "Account" in the sidebar navigates to '
        'account', (tester) async {
      _setViewportWidth(tester, 1000);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: _buildTestRouter()),
        ),
      );

      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();

      expect(find.text('Account screen'), findsOneWidget);
    });

    testWidgets(
      'wide: the Account branch keeps the persistent sidebar visible, '
      'same as every other branch',
      (tester) async {
        _setViewportWidth(tester, 1000);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(routerConfig: _buildTestRouter()),
          ),
        );

        await tester.tap(find.text('Account'));
        await tester.pumpAndSettle();

        // Unlike a route pushed on top of the shell, a branch keeps the
        // sidebar (and every other destination) on screen alongside it.
        expect(find.byType(NavigationDrawer), findsOneWidget);
        expect(find.text('Now'), findsOneWidget);
        expect(find.text('Day'), findsOneWidget);
        expect(find.text('Templates'), findsOneWidget);
        expect(find.text('Categories'), findsOneWidget);
        expect(find.text('Tasks'), findsOneWidget);
        expect(find.text('Account screen'), findsOneWidget);
      },
    );

    testWidgets(
      'narrow: the Account branch is reachable via the drawer, same as '
      'every other branch, and switching away and back preserves its state',
      (tester) async {
        _setViewportWidth(tester, 600);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(routerConfig: _buildTestRouter()),
          ),
        );

        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Account'));
        await tester.pumpAndSettle();
        expect(find.text('Account screen'), findsOneWidget);

        // Switch to another branch and back — a StatefulShellBranch (not
        // a plain pushed route) keeps its Navigator/state alive rather
        // than rebuilding from scratch.
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Templates'));
        await tester.pumpAndSettle();
        expect(find.text('Branch two'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Account'));
        await tester.pumpAndSettle();
        expect(find.text('Account screen'), findsOneWidget);
      },
    );
  });
}
