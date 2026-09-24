import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:taskframe/core/widgets/app_shell.dart';
import 'package:taskframe/features/saved_search/providers.dart';

void _setViewportWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renaming a saved view uses a 16px+ font, so iOS Safari never '
      'auto-zooms the page on focus and leaves it stuck zoomed in '
      '(standalone PWA mode has no chrome to manually zoom back out)', (
    tester,
  ) async {
    _setViewportWidth(tester, 1000);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(savedSearchListProvider.future);
    await container.read(savedSearchListProvider.notifier).addView('#a');

    final router = GoRouter(
      initialLocation: '/day',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/day',
                  builder: (context, state) => const Text('Day branch'),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Tasks view 1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    final fontSize = field.style!.fontSize!;
    expect(fontSize, greaterThanOrEqualTo(16));
  });
}
