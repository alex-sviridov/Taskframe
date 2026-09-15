import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/template/widgets/templates_screen.dart';

void _resizeViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: TemplatesScreen())),
  );
  await tester.pump();
}

void main() {
  group('TemplatesScreen', () {
    testWidgets('starts with no templates and an add button', (tester) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);

      expect(find.widgetWithText(AppBar, 'Templates'), findsOneWidget);
      expect(find.byTooltip('Add template'), findsOneWidget);
    });

    testWidgets('the add button creates a template named "Template 1"', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);

      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();

      expect(find.text('Template 1'), findsOneWidget);
    });

    testWidgets('a second added template is named "Template 2"', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(1200, 1000));
      await _pump(tester);

      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();

      expect(find.text('Template 1'), findsOneWidget);
      expect(find.text('Template 2'), findsOneWidget);
    });

    testWidgets('adding after a delete does not reuse a name already in use '
        '(regression: the default name was derived from the template count, '
        'so add/add/delete-first/add produced two "Template 2"s)', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(1200, 1000));
      await _pump(tester);
      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete template').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();

      expect(find.text('Template 1'), findsNothing);
      expect(find.text('Template 2'), findsOneWidget);
      expect(find.text('Template 3'), findsOneWidget);
    });

    testWidgets('the delete action on a column removes that template', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);
      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete template'));
      await tester.pumpAndSettle();

      expect(find.text('Template 1'), findsNothing);
      expect(find.byTooltip('Add template'), findsOneWidget);
    });

    testWidgets('on a narrow width, adding two templates pages to the second '
        'with the next-template arrow', (tester) async {
      _resizeViewport(tester, const Size(500, 1000));
      await _pump(tester);
      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add template'));
      await tester.pumpAndSettle();
      // Adding opens straight to the new template, so we're on
      // "Template 2"; page back to confirm "Template 1" is reachable.
      expect(find.byTooltip('Previous template'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous template'));
      await tester.pumpAndSettle();

      expect(find.text('Template 1'), findsOneWidget);
    });

    testWidgets(
      'a horizontal fling on free grid space swipes to the next template',
      (tester) async {
        _resizeViewport(tester, const Size(500, 1000));
        await _pump(tester);
        await tester.tap(find.byTooltip('Add template'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Add template'));
        await tester.pumpAndSettle();
        // Adding opens straight to the new template ("Template 2"); page
        // back to "Template 1" first so there's somewhere to swipe
        // forward to.
        await tester.tap(find.byTooltip('Previous template'));
        await tester.pumpAndSettle();
        expect(find.text('Template 1'), findsOneWidget);

        final gridTop = tester.getTopLeft(find.byType(DayGrid));
        await tester.flingFrom(
          gridTop + const Offset(50, 5),
          const Offset(-300, 0),
          1000,
        );
        await tester.pumpAndSettle();

        expect(find.text('Template 1'), findsNothing);
        expect(find.text('Template 2'), findsOneWidget);
      },
    );

    testWidgets(
      'at a wide width, an 8th template pages to a second, capped-at-7 page',
      (tester) async {
        _resizeViewport(tester, const Size(1200, 1000));
        await _pump(tester);
        for (var i = 0; i < 8; i++) {
          await tester.tap(find.byTooltip('Add template'));
          await tester.pumpAndSettle();
        }
        // Adding opens straight to the new template's page, so "Template 8"
        // is alone on page two; templates 1-7 are on page one.
        expect(find.text('Template 8'), findsOneWidget);
        for (var i = 1; i <= 7; i++) {
          expect(find.text('Template $i'), findsNothing);
        }
        expect(find.byTooltip('Previous templates'), findsOneWidget);

        await tester.tap(find.byTooltip('Previous templates'));
        await tester.pumpAndSettle();

        expect(find.text('Template 8'), findsNothing);
        for (var i = 1; i <= 7; i++) {
          expect(find.text('Template $i'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'tapping a column opens the block edit modal without a date row or '
      'copy button',
      (tester) async {
        _resizeViewport(tester, const Size(800, 1000));
        await _pump(tester);
        await tester.tap(find.byTooltip('Add template'));
        await tester.pumpAndSettle();

        await tester.longPressAt(const Offset(200, 192));
        await tester.pump();
        expect(find.byIcon(Icons.event), findsWidgets); // draft overlay open

        await tester.tap(find.byIcon(Icons.event).last);
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.calendar_today), findsNothing);
        expect(find.byTooltip('Copy to next day'), findsNothing);
      },
    );
  });
}
