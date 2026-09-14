import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/widgets/app_shell.dart';
import 'package:taskframe/features/saved_search/data/saved_search_repository.dart';
import 'package:taskframe/features/saved_search/providers.dart';

void _setViewportWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: '/tasks',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const Text('Day')),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tasks',
              builder: (context, state) => Text(
                'Tasks screen: q=${state.uri.queryParameters['q'] ?? ''}',
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<InMemorySavedSearchRepository> _seedOneView(WidgetTester tester) async {
  final repository = InMemorySavedSearchRepository();
  await repository.add(name: 'Urgent work', query: '#urgent');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [savedSearchRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: _buildRouter()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  group('Saved views sidebar', () {
    testWidgets('hidden when there are no saved views', (tester) async {
      _setViewportWidth(tester, 1000);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: _buildRouter())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved views'), findsNothing);
    });

    testWidgets('shows each saved view by name, wide sidebar', (tester) async {
      _setViewportWidth(tester, 1000);
      await _seedOneView(tester);

      expect(find.text('Saved views'), findsOneWidget);
      expect(find.text('Urgent work'), findsOneWidget);
    });

    testWidgets('tapping a saved view loads its query into Tasks', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);
      await _seedOneView(tester);

      await tester.tap(find.text('Urgent work'));
      await tester.pumpAndSettle();

      expect(find.text('Tasks screen: q=#urgent'), findsOneWidget);
    });

    testWidgets('narrow: shows saved views in the open drawer', (tester) async {
      _setViewportWidth(tester, 600);
      await _seedOneView(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Urgent work'), findsOneWidget);
    });

    testWidgets('wide: hovering a row reveals the overflow menu', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);
      await _seedOneView(tester);

      expect(find.byIcon(Icons.more_vert), findsNothing);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('Urgent work')));
      await tester.pump();

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('narrow: long-pressing a row reveals the overflow menu', (
      tester,
    ) async {
      _setViewportWidth(tester, 600);
      await _seedOneView(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert), findsNothing);
      await tester.longPress(find.text('Urgent work'));
      await tester.pump();

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('renaming a view updates its label', (tester) async {
      _setViewportWidth(tester, 600);
      await _seedOneView(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Urgent work'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'Renamed view');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Renamed view'), findsOneWidget);
      expect(find.text('Urgent work'), findsNothing);
    });

    testWidgets('deleting a view removes it from the sidebar', (tester) async {
      _setViewportWidth(tester, 600);
      await _seedOneView(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Urgent work'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Urgent work'), findsNothing);
      expect(find.text('Saved views'), findsNothing);
    });
  });
}
