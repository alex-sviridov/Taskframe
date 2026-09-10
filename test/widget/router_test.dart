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
