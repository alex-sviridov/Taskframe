import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
import 'package:taskframe/features/template/models/template.dart';
import 'package:taskframe/features/template/providers.dart';
import 'package:taskframe/router.dart';

void _resizeViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Starts a touch drag the way `DayGrid`'s move recognizer expects: press,
/// then wait out the long-press timeout that distinguishes a move from a
/// scroll. Mirrors `day_grid_test.dart`'s helper of the same name.
Future<TestGesture> _startTouchDrag(
  WidgetTester tester,
  Offset position,
) async {
  final gesture = await tester.startGesture(position);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return gesture;
}

/// Pumps the real [appRouter], visits the Day branch (so its `DayColumn`
/// grid keys get memoized first), then switches to Templates, adds one
/// template and seeds it with a block. Returns that template.
Future<Template> _pumpBothBranchesWithTemplateBlock(
  WidgetTester tester,
  ProviderContainer container,
) async {
  appRouter.go('/day');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: appRouter),
    ),
  );
  await tester.pumpAndSettle();
  // The Day branch must actually have built its grid, or there would be no
  // stale DayColumn candidate for the regression to trip over.
  expect(find.byType(DayGrid), findsWidgets);

  await tester.tap(find.text('Templates'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Add template'));
  await tester.pumpAndSettle();

  final template = (await container.read(templateListProvider.future)).single;
  await container
      .read(templateBlocksProvider(template.id).notifier)
      .addBlock(
        start: templateAnchorDate.add(const Duration(hours: 9)),
        end: templateAnchorDate.add(const Duration(hours: 10)),
        kind: BlockKind.frame,
        title: 'Template block',
      );
  await tester.pumpAndSettle();
  return template;
}

void main() {
  group('dragging through the real appRouter with both branches built', () {
    testWidgets(
      'a template block resolves a TemplateColumn target, never the Day '
      "branch's offstage DayColumn (regression: an indexedStack shell "
      'lays out every branch even while offstage, so a rect '
      'test alone matched a DayColumn and crashed the cast in '
      'TemplateScheduleController)',
      (tester) async {
        _resizeViewport(tester, const Size(1200, 1400));
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final template = await _pumpBothBranchesWithTemplateBlock(
          tester,
          container,
        );

        final resolved = resolveDragTarget(
          globalPosition: tester.getCenter(find.byType(DayGrid)),
          origin: TemplateColumn(template.id),
          settings: container.read(daySettingsProvider),
          slotHeight: 16,
          blockDuration: const Duration(hours: 1),
        );

        expect(
          resolved?.column,
          isA<TemplateColumn>(),
          reason:
              'a drag originating on a TemplateColumn must never resolve a '
              "DayColumn, even though the Day branch's grid was laid out "
              'first and reports an overlapping global rect while offstage',
        );
        expect(resolved?.column, TemplateColumn(template.id));
      },
    );

    testWidgets(
      'dragging a template block moves it within its own template instead '
      'of throwing on a DayColumn target',
      (tester) async {
        _resizeViewport(tester, const Size(1200, 1400));
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final template = await _pumpBothBranchesWithTemplateBlock(
          tester,
          container,
        );
        final before = (await container.read(
          templateBlocksProvider(template.id).future,
        )).single;

        final start = tester.getCenter(find.text('Template block'));
        final gesture = await _startTouchDrag(tester, start);
        await gesture.moveBy(const Offset(0, 64));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        // A cross-variant resolve used to surface here as a TypeError from
        // `(column as TemplateColumn)`; pumpAndSettle would have rethrown it.
        expect(tester.takeException(), isNull);

        final after = (await container.read(
          templateBlocksProvider(template.id).future,
        )).single;
        expect(after.id, before.id);
        expect(
          after.start.isAfter(before.start),
          isTrue,
          reason:
              'the drop should have committed a move down inside the '
              'template column',
        );
        expect(
          after.end.difference(after.start),
          before.end.difference(before.start),
        );
      },
    );
  });
}
