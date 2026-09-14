import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/widgets/app_shell.dart';
import 'package:taskframe/features/saved_search/data/saved_search_repository.dart';
import 'package:taskframe/features/saved_search/providers.dart';

/// The overflow menu/drag handle icons are always present in the row's
/// widget tree (only their [Opacity]/[IgnorePointer] wrapper toggles),
/// so "revealed" is asserted via that wrapper's opacity, not via presence
/// in a `find.byIcon` match.
double _rowAffordanceOpacity(WidgetTester tester) {
  final opacity = tester.widget<Opacity>(
    find.ancestor(
      of: find.byIcon(Icons.more_vert),
      matching: find.byType(Opacity),
    ),
  );
  return opacity.opacity;
}

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

      expect(_rowAffordanceOpacity(tester), 0);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('Urgent work')));
      await tester.pump();

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(_rowAffordanceOpacity(tester), 1);
    });

    testWidgets('narrow: long-pressing a row reveals the overflow menu', (
      tester,
    ) async {
      _setViewportWidth(tester, 600);
      await _seedOneView(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(_rowAffordanceOpacity(tester), 0);
      await tester.longPress(find.text('Urgent work'));
      await tester.pump();

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(_rowAffordanceOpacity(tester), 1);
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

    testWidgets('two saved views can be reordered by dragging the handle', (
      tester,
    ) async {
      _setViewportWidth(tester, 1000);
      final repository = InMemorySavedSearchRepository();
      await repository.add(name: 'First', query: '#a');
      await repository.add(name: 'Second', query: '#b');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            savedSearchRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(routerConfig: _buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      // Reveal the row affordances (drag handle + overflow menu) the same
      // way the hover test above does, since they're hidden until then.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('First')));
      await tester.pump();

      final firstHandleFinder = find.byIcon(Icons.drag_indicator).first;
      final secondRowFinder = find.text('Second');
      final handleCenter = tester.getCenter(firstHandleFinder);
      final targetCenter = tester.getCenter(secondRowFinder);
      await gesture.moveTo(handleCenter);
      await tester.pump();
      await gesture.down(handleCenter);
      await tester.pump(const Duration(milliseconds: 100));
      // ReorderableDragStartListener needs the drag recognized via a few
      // incremental moves (matching real pointer movement) rather than one
      // instantaneous jump to the target.
      const steps = 6;
      for (var i = 1; i <= steps; i++) {
        final t = i / steps;
        await gesture.moveTo(Offset.lerp(handleCenter, targetCenter, t)!);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final rowTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((t) => t == 'First' || t == 'Second')
          .toList();
      expect(rowTexts, ['Second', 'First']);
    });
  });
}
