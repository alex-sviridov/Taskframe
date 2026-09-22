import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/template/providers.dart';
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

/// Taps the trailing "+" add-template slot. Callers must already be on the
/// page it's showing on (it only exists right after the last template).
Future<void> _tapAddTemplateSlot(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Add template'));
  await tester.pumpAndSettle();
}

void main() {
  group('TemplatesScreen', () {
    testWidgets('starts with no templates and an add-template slot', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);

      expect(find.widgetWithText(AppBar, 'Templates'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Add template'),
        findsOneWidget,
      );
      // No template to add a block to yet, so the AppBar button is
      // disabled.
      final addBlockButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Add block'),
          matching: find.byType(IconButton),
        ),
      );
      expect(addBlockButton.onPressed, isNull);
    });

    testWidgets(
      'tapping the add-template slot creates a template named "Template 1"',
      (tester) async {
        _resizeViewport(tester, const Size(800, 1000));
        await _pump(tester);

        await _tapAddTemplateSlot(tester);

        expect(find.text('Template 1'), findsOneWidget);
      },
    );

    testWidgets('a second added template is named "Template 2"', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(1200, 1000));
      await _pump(tester);

      await _tapAddTemplateSlot(tester);
      await _tapAddTemplateSlot(tester);

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
      await _tapAddTemplateSlot(tester);
      await _tapAddTemplateSlot(tester);

      await tester.tap(find.byTooltip('Delete template').first);
      await tester.pumpAndSettle();
      await _tapAddTemplateSlot(tester);

      expect(find.text('Template 1'), findsNothing);
      expect(find.text('Template 2'), findsOneWidget);
      expect(find.text('Template 3'), findsOneWidget);
    });

    testWidgets('the delete action on a column removes that template', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);
      await _tapAddTemplateSlot(tester);

      await tester.tap(find.byTooltip('Delete template'));
      await tester.pumpAndSettle();

      expect(find.text('Template 1'), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, 'Add template'),
        findsOneWidget,
      );
    });

    testWidgets('on a narrow width, adding two templates pages to the second '
        'with the next-template arrow', (tester) async {
      _resizeViewport(tester, const Size(500, 1000));
      await _pump(tester);
      await _tapAddTemplateSlot(tester);
      // Adding opens straight to the new template, so the add-template
      // slot is now on the next page, reachable via the next-template
      // arrow.
      expect(find.byTooltip('Next template'), findsOneWidget);
      await tester.tap(find.byTooltip('Next template'));
      await tester.pumpAndSettle();
      await _tapAddTemplateSlot(tester);
      // Adding again opens straight to "Template 2"; page back to confirm
      // "Template 1" is reachable.
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
        await _tapAddTemplateSlot(tester);
        await tester.tap(find.byTooltip('Next template'));
        await tester.pumpAndSettle();
        await _tapAddTemplateSlot(tester);
        // Adding opens straight to "Template 2"; page back to "Template 1"
        // first so there's somewhere to swipe forward to.
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
        for (var i = 0; i < 7; i++) {
          await _tapAddTemplateSlot(tester);
        }
        // The 7 real templates fill page one; the add-template slot is
        // alone on page two.
        expect(find.byTooltip('Previous templates'), findsOneWidget);
        await tester.tap(find.byTooltip('Next templates'));
        await tester.pumpAndSettle();
        await _tapAddTemplateSlot(tester);

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
        // Narrow so the lone real template is alone on its page (a single
        // column, full width) rather than sharing the row with the
        // trailing add-template slot.
        _resizeViewport(tester, const Size(500, 1000));
        await _pump(tester);
        await _tapAddTemplateSlot(tester);

        await tester.longPressAt(const Offset(200, 192));
        await tester.pump();
        expect(find.byIcon(Icons.event), findsWidgets); // draft overlay open

        await tester.tap(find.byIcon(Icons.event).last);
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.calendar_today), findsNothing);
        expect(find.byTooltip('Copy to next day'), findsNothing);
      },
    );

    testWidgets(
      'the delete button is not obscured by the next-template arrow at a '
      'narrow width (regression: a single-column header centered its '
      'content across the full width, putting the delete button under '
      'the arrow)',
      (tester) async {
        _resizeViewport(tester, const Size(500, 1000));
        await _pump(tester);
        await _tapAddTemplateSlot(tester);
        await tester.tap(find.byTooltip('Next template'));
        await tester.pumpAndSettle();
        await _tapAddTemplateSlot(tester);
        await tester.tap(find.byTooltip('Previous template'));
        await tester.pumpAndSettle();

        final deleteRight = tester
            .getTopRight(find.byTooltip('Delete template'))
            .dx;
        final arrowLeft = tester.getTopLeft(find.byTooltip('Next template')).dx;
        expect(deleteRight, lessThanOrEqualTo(arrowLeft));
      },
    );

    testWidgets('editing a template name autosaves after a pause, without '
        'pressing enter', (tester) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);
      await _tapAddTemplateSlot(tester);

      await tester.enterText(find.text('Template 1'), 'Morning routine');
      // Not settled/submitted yet, so the rename hasn't landed.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TemplatesScreen)),
      );
      expect(
        container.read(templateListProvider).value!.single.name,
        'Template 1',
      );

      await tester.pump(const Duration(milliseconds: 600));

      expect(
        container.read(templateListProvider).value!.single.name,
        'Morning routine',
      );
    });

    testWidgets(
      'the AppBar add button adds a block to the first template on the '
      'current page',
      (tester) async {
        _resizeViewport(tester, const Size(800, 1000));
        await _pump(tester);
        await _tapAddTemplateSlot(tester);

        await tester.tap(find.byTooltip('Add block'));
        await tester.pumpAndSettle();

        // The block edit modal opened for a freshly created block.
        expect(find.byIcon(Icons.calendar_today), findsNothing);
        expect(find.byTooltip('Copy to next day'), findsNothing);
      },
    );
  });
}
