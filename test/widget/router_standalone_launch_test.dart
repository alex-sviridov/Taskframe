import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/router.dart';

void main() {
  group('createAppRouter standalone-launch redirect', () {
    testWidgets('a standalone launch straight into /account redirects to /day '
        '(iOS pins the PWA to whichever URL was open when it was added to '
        'the home screen, ignoring the web manifest start_url)', (
      tester,
    ) async {
      final router = createAppRouter(isStandalone: () => true)..go('/account');

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pump();

      expect(find.text('Day Frame'), findsOneWidget);
    });

    testWidgets('a non-standalone (ordinary browser tab) launch straight into '
        '/tasks is left alone, preserving deep links on refresh', (
      tester,
    ) async {
      final router = createAppRouter(isStandalone: () => false)..go('/tasks');

      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pump();

      expect(find.text('Day Frame'), findsNothing);
      expect(find.text('Tasks'), findsWidgets);
    });

    testWidgets(
      'after the first navigation, a standalone launch no longer forces '
      '/day on later navigations',
      (tester) async {
        final router = createAppRouter(isStandalone: () => true)
          ..go('/account');

        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)),
        );
        await tester.pump();

        router.go('/account');
        await tester.pump();

        expect(find.text('Account'), findsWidgets);
      },
    );
  });
}
