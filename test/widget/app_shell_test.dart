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
      ],
    ),
    GoRoute(
      path: '/pairing',
      builder: (context, state) => const Text('Pairing screen'),
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
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
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

    testWidgets(
      'narrow: tapping "Sync devices" in the open drawer navigates to '
      'pairing',
      (tester) async {
        _setViewportWidth(tester, 600);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(routerConfig: _buildTestRouter()),
          ),
        );

        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sync devices'));
        await tester.pumpAndSettle();

        expect(find.text('Pairing screen'), findsOneWidget);
      },
    );

    testWidgets('wide: tapping "Sync devices" in the sidebar navigates to '
        'pairing', (tester) async {
      _setViewportWidth(tester, 1000);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: _buildTestRouter()),
        ),
      );

      await tester.tap(find.text('Sync devices'));
      await tester.pumpAndSettle();

      expect(find.text('Pairing screen'), findsOneWidget);
    });
  });
}
