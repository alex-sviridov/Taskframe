import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/widgets/app_shell.dart';
import 'package:taskframe/router.dart';

void main() {
  group('appRouter', () {
    setUp(() => appRouter.go('/'));

    testWidgets(
      '/ redirects to /now, shown inside the shell with Now selected',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
        );
        await tester.pump();

        expect(find.byType(AppShell), findsOneWidget);
        expect(find.text('Now'), findsWidgets);
        final shell = tester.widget<AppShell>(find.byType(AppShell));
        expect(shell.navigationShell.currentIndex, 0);
      },
    );

    testWidgets('tapping Day navigates to /day', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
      );
      await tester.pump();

      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();

      expect(find.text('Day Frame'), findsOneWidget);
      final shell = tester.widget<AppShell>(find.byType(AppShell));
      expect(shell.navigationShell.currentIndex, 1);
    });

    testWidgets('tapping Categories navigates to /categories', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
      );
      await tester.pump();

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsWidgets);
      expect(find.text('Default'), findsOneWidget);
      final shell = tester.widget<AppShell>(find.byType(AppShell));
      expect(shell.navigationShell.currentIndex, 3);
    });

    testWidgets('tapping Templates navigates to /templates', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
      );
      await tester.pump();

      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();

      expect(find.text('Templates'), findsWidgets);
      final shell = tester.widget<AppShell>(find.byType(AppShell));
      expect(shell.navigationShell.currentIndex, 2);
    });

    testWidgets('tapping Tasks navigates to /tasks', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
      );
      await tester.pump();

      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();

      expect(find.text('Tasks'), findsWidgets);
      final shell = tester.widget<AppShell>(find.byType(AppShell));
      expect(shell.navigationShell.currentIndex, 4);
    });

    testWidgets(
      "DayScreen's paged-forward state survives switching branches and back",
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: appRouter)),
        );
        await tester.pump();

        await tester.tap(find.text('Day'));
        await tester.pumpAndSettle();

        final initialLabel = tester
            .widget<Text>(find.byKey(const Key('day-screen-date-label')))
            .data;

        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();

        final pagedLabel = tester
            .widget<Text>(find.byKey(const Key('day-screen-date-label')))
            .data;
        expect(pagedLabel, isNot(equals(initialLabel)));

        await tester.tap(find.text('Categories'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Day'));
        await tester.pumpAndSettle();

        final labelAfterReturn = tester
            .widget<Text>(find.byKey(const Key('day-screen-date-label')))
            .data;
        expect(labelAfterReturn, equals(pagedLabel));
      },
    );
  });
}
