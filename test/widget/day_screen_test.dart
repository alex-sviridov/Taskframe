import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_screen.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: DayScreen())),
  );
  // Flushes the day blocks provider's initial load.
  await tester.pump();
}

void _resizeViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('DayScreen', () {
    testWidgets("shows the app title and today's hardcoded blocks", (
      tester,
    ) async {
      await _pump(tester);

      expect(find.widgetWithText(AppBar, 'Day Frame'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('the next-day arrow switches to a day with no blocks', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();

      expect(find.text('Breakfast'), findsNothing);
    });

    testWidgets("the previous-day arrow returns to today's blocks", (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();

      expect(find.text('Breakfast'), findsOneWidget);
    });

    testWidgets('the date label updates when switching days', (tester) async {
      await _pump(tester);

      final before = tester
          .widget<Text>(find.byKey(const Key('day-screen-date-label')))
          .data;

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();

      final after = tester
          .widget<Text>(find.byKey(const Key('day-screen-date-label')))
          .data;

      expect(after, isNot(equals(before)));
    });

    testWidgets('grows the grid slot height to fill a tall viewport', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 5000));

      await _pump(tester);

      final grid = tester.widget<DayGrid>(find.byType(DayGrid));
      expect(grid.slotHeight, greaterThan(16));
    });

    testWidgets('clamps the grid slot height on a very short viewport', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 300));

      await _pump(tester);

      final grid = tester.widget<DayGrid>(find.byType(DayGrid));
      expect(grid.slotHeight, 8);
    });

    testWidgets('double-tapping free space and confirming adds a new block', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      final gridTop = tester.getTopLeft(find.byType(DayGrid));
      // A few pixels into the grid is always before Breakfast (7:00),
      // so it's free space regardless of the fitted slot height.
      final freeSpace = gridTop + const Offset(50, 5);

      await tester.tapAt(freeSpace);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(freeSpace);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.bySemanticsLabel('Create Event'));
      await tester.pump();

      expect(find.text('title'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a horizontal fling on free grid space switches the day', (
      tester,
    ) async {
      await _pump(tester);

      // A few pixels into the grid is always before Breakfast (7:00),
      // so it's free space regardless of the fitted slot height.
      final gridTop = tester.getTopLeft(find.byType(DayGrid));
      await tester.flingFrom(
        gridTop + const Offset(50, 5),
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('Breakfast'), findsNothing);
    });
  });
}
