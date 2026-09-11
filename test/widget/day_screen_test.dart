import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_screen.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';

/// Mirrors the field-based date arithmetic `_startDateForPage` and
/// `_SchedulePage`'s `dates` list in day_screen.dart use, so DST/month-
/// boundary correctness can be exercised without a widget pump.
DateTime _addCalendarDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

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

/// The current time rounded down to the 15-minute grid `TimeObject`
/// requires, so ad-hoc test blocks satisfy its on-grid assertion
/// regardless of when the test runs.
DateTime _nowOnGrid() {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute ~/ 15 * 15,
  );
}

void main() {
  group('DayScreen', () {
    testWidgets("shows the app title and today's hardcoded blocks", (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);

      expect(find.widgetWithText(AppBar, 'Day Frame'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('the next-day arrow switches to a day with no blocks', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();

      expect(find.text('Breakfast'), findsNothing);
    });

    testWidgets("the previous-day arrow returns to today's blocks", (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();

      expect(find.text('Breakfast'), findsOneWidget);
    });

    testWidgets('the date label updates when switching days', (tester) async {
      _resizeViewport(tester, const Size(800, 1000));
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
      _resizeViewport(tester, const Size(800, 1000));
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

      // findsWidgets, not findsOneWidget: creating a block now also opens
      // its edit modal (see the next test), whose title field echoes the
      // same default "title" text alongside the block's own label on the
      // grid.
      expect(find.text('title'), findsWidgets);
      semantics.dispose();
    });

    testWidgets('creating a block immediately opens its edit modal', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      final gridTop = tester.getTopLeft(find.byType(DayGrid));
      final freeSpace = gridTop + const Offset(50, 5);

      await tester.tapAt(freeSpace);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(freeSpace);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.bySemanticsLabel('Create Event'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the add button creates a block in the next free slot and '
        'opens its edit modal', (tester) async {
      _resizeViewport(tester, const Size(800, 1000));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Fixed, far-past date: InMemoryDayBlocksRepository only seeds
      // hardcoded blocks for the real wall-clock "today", so this date
      // starts out empty and the free slot lands exactly at day start.
      final date = DateTime(2000);
      container.read(selectedDateProvider.notifier).date = date;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DayScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Add block'));
      await tester.pumpAndSettle();

      final settings = container.read(daySettingsProvider);
      final blocks = container.read(dayBlocksProvider(date)).value!;
      expect(blocks, hasLength(1));
      expect(blocks.single.start, DateTime(2000, 1, 1, settings.dayStartHour));
      expect(find.byType(BlockEditModal), findsOneWidget);
    });

    testWidgets('a horizontal fling on free grid space switches the day', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
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

    testWidgets('shows a full week of grids on a wide viewport', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(1000, 800));

      await _pump(tester);

      expect(find.byType(DayGrid), findsNWidgets(7));
    });

    testWidgets('omits the weekday name from headers in week view', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(1000, 800));

      await _pump(tester);

      expect(find.textContaining('day,'), findsNothing);
    });

    testWidgets(
      'switching from day to week view keeps the selected date visible',
      (tester) async {
        _resizeViewport(tester, const Size(800, 1000));
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: DayScreen()),
          ),
        );
        await tester.pump();

        await tester.tap(find.byTooltip('Next day'));
        await tester.pumpAndSettle();

        final selected = container.read(selectedDateProvider);

        _resizeViewport(tester, const Size(1000, 800));
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            Key('day-screen-date-label-${selected.toIso8601String()}'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'pinned Monday-first week shows the exact expected dates in order',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        // Wednesday 2026-09-09.
        container.read(selectedDateProvider.notifier).date = DateTime(
          2026,
          9,
          9,
        );

        _resizeViewport(tester, const Size(1000, 800));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: DayScreen()),
          ),
        );
        await tester.pump();

        final expectedDates = List.generate(7, (i) => DateTime(2026, 9, 7 + i));
        for (final date in expectedDates) {
          expect(
            find.byKey(Key('day-screen-date-label-${date.toIso8601String()}')),
            findsOneWidget,
            reason: 'expected a header for ${date.toIso8601String()}',
          );
        }

        // Also assert left-to-right order matches the expected sequence.
        final headerRow = tester.widget<Row>(
          find
              .ancestor(
                of: find.byKey(
                  Key(
                    'day-screen-date-label-'
                    '${expectedDates.first.toIso8601String()}',
                  ),
                ),
                matching: find.byType(Row),
              )
              .first,
        );
        final labelKeys = headerRow.children
            .whereType<Expanded>()
            .map((expanded) => expanded.child)
            .whereType<Center>()
            .map((center) => center.child)
            .whereType<Semantics>()
            .map((semantics) => semantics.child)
            .whereType<Text>()
            .map((text) => text.key)
            .toList();
        expect(
          labelKeys,
          expectedDates
              .map(
                (date) =>
                    Key('day-screen-date-label-${date.toIso8601String()}'),
              )
              .toList(),
        );
      },
    );

    testWidgets(
      'a Sunday-first week setting starts the week on the correct Sunday',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        // Wednesday 2026-09-09.
        container.read(selectedDateProvider.notifier).date = DateTime(
          2026,
          9,
          9,
        );

        _resizeViewport(tester, const Size(1000, 800));
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: ProviderScope(
              overrides: [
                daySettingsProvider.overrideWithValue(
                  const DaySettings(
                    dayStartHour: 6,
                    dayEndHour: 23,
                    firstDayOfWeek: DateTime.sunday,
                    dateFormat: 'dd/MM/yyyy',
                  ),
                ),
              ],
              child: const MaterialApp(home: DayScreen()),
            ),
          ),
        );
        await tester.pump();

        // Sunday 2026-09-06, one day before the Monday-first week's start.
        final expectedFirstDay = DateTime(2026, 9, 6);
        expect(
          find.byKey(
            Key(
              'day-screen-date-label-'
              '${expectedFirstDay.toIso8601String()}',
            ),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('calendar-date arithmetic (DST/month-boundary safety)', () {
    test('adding days across a month boundary yields distinct consecutive '
        'calendar dates', () {
      final start = DateTime(2026, 1, 28);
      final dates = List.generate(40, (i) => _addCalendarDays(start, i));

      // All dates distinct.
      expect(dates.toSet().length, dates.length);

      // Each date is exactly one calendar day after the previous one.
      for (var i = 1; i < dates.length; i++) {
        final expectedNext = DateTime(
          dates[i - 1].year,
          dates[i - 1].month,
          dates[i - 1].day + 1,
        );
        expect(dates[i], expectedNext);
      }
    });

    test('Duration-based arithmetic (the old, buggy approach) can collapse '
        'two distinct calendar days into the same instant across a DST '
        'transition', () {
      // This test documents *why* the fix in day_screen.dart matters.
      // Whether it actually demonstrates a collision depends on the
      // host's local timezone observing DST on this date; in a
      // UTC-only sandbox (no DST), `.add(Duration(days: 1))` still
      // produces the calendar-correct next day, so this assertion is
      // a no-op there. Real DST-crossing coverage needs a
      // timezone-aware test harness this project doesn't have yet.
      final beforeTransition = DateTime(2026, 11, 1, 23);
      final durationBased = beforeTransition.add(const Duration(days: 1));
      final fieldBased = DateTime(
        beforeTransition.year,
        beforeTransition.month,
        beforeTransition.day + 1,
        beforeTransition.hour,
      );

      // The field-based (fixed) approach always lands on the correct
      // next calendar day, regardless of DST.
      expect(fieldBased.day, beforeTransition.day + 1);
      expect(fieldBased.year, beforeTransition.year);
      expect(fieldBased.month, beforeTransition.month);

      // In a timezone with no DST transition on this date (e.g. UTC,
      // which this sandbox runs in), Duration-based and field-based
      // arithmetic agree.
      expect(durationBased, fieldBased);
    });
  });

  group('edge-triggered paging during a drag', () {
    testWidgets('dwelling in the left edge zone pages to the previous day', (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DayScreen()),
        ),
      );
      await tester.pump();

      final start = _nowOnGrid();
      final block = TimeObject(
        id: 'dragged',
        title: 'Breakfast',
        start: start,
        end: start.add(const Duration(minutes: 30)),
        kind: BlockKind.anchor,
        locked: false,
      );
      container
          .read(dragStateProvider.notifier)
          .start(
            block: block,
            originalDate: container.read(selectedDateProvider),
            pointerGlobalPosition: const Offset(500, 500),
          );

      container
          .read(dragStateProvider.notifier)
          .updatePointer(const Offset(10, 500));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();

      expect(find.text('Breakfast'), findsNothing);
    });

    testWidgets(
      'dwelling near the left edge of a rail-inset DayScreen (not the '
      "window's left edge) still pages to the previous day",
      (tester) async {
        // Simulates a NavigationRail (72px + a 1px VerticalDivider,
        // rounded up to 100px here) eating the left side of the window,
        // so DayScreen's own local left edge sits well inside the window
        // rather than at its left edge.
        const railWidth = 100.0;
        _resizeViewport(tester, const Size(800, 1000));
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: Row(
                  children: [
                    SizedBox(width: railWidth),
                    Expanded(child: DayScreen()),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final start = _nowOnGrid();
        final block = TimeObject(
          id: 'dragged',
          title: 'Breakfast',
          start: start,
          end: start.add(const Duration(minutes: 30)),
          kind: BlockKind.anchor,
          locked: false,
        );
        container
            .read(dragStateProvider.notifier)
            .start(
              block: block,
              originalDate: container.read(selectedDateProvider),
              pointerGlobalPosition: const Offset(500, 500),
            );

        // Global x=150 is 50px inside DayScreen's own local left edge
        // (which starts at global x=100, past the simulated rail) — within
        // `_edgeFadeWidth` (72) of DayScreen's local edge, but nowhere near
        // the *window's* left edge or right edge. Only a fix that measures
        // the drag in DayScreen-local coordinates should treat this as an
        // edge dwell.
        container
            .read(dragStateProvider.notifier)
            .updatePointer(const Offset(150, 500));
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pumpAndSettle();

        expect(find.text('Breakfast'), findsNothing);
      },
    );

    testWidgets('leaving the edge zone before the dwell time cancels the '
        'page turn', (tester) async {
      _resizeViewport(tester, const Size(800, 1000));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DayScreen()),
        ),
      );
      await tester.pump();

      final start = _nowOnGrid();
      final block = TimeObject(
        id: 'dragged',
        title: 'Breakfast',
        start: start,
        end: start.add(const Duration(minutes: 30)),
        kind: BlockKind.anchor,
        locked: false,
      );
      container
          .read(dragStateProvider.notifier)
          .start(
            block: block,
            originalDate: container.read(selectedDateProvider),
            pointerGlobalPosition: const Offset(500, 500),
          );

      container
          .read(dragStateProvider.notifier)
          .updatePointer(const Offset(10, 500));
      await tester.pump(const Duration(milliseconds: 300));
      container
          .read(dragStateProvider.notifier)
          .updatePointer(const Offset(400, 500));
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();

      expect(find.text('Breakfast'), findsOneWidget);
    });
  });

  group('resolveDragTarget through the real day_screen.dart week view', () {
    testWidgets('finds a target in a second, non-origin column '
        '(regression: column lookup must not depend on DateTime object '
        'identity)', (tester) async {
      _resizeViewport(tester, const Size(1000, 800));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Wednesday 2026-09-09.
      container.read(selectedDateProvider.notifier).date = DateTime(2026, 9, 9);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DayScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(DayGrid), findsNWidgets(7));

      final firstGrid = tester.widget<DayGrid>(find.byType(DayGrid).first);
      final settings = container.read(daySettingsProvider);
      final slotHeight = firstGrid.slotHeight;

      // Target a point inside the second column (index 1), which is not
      // where any drag would "start" (the origin/first column).
      //
      // Two identity traps have to stay fixed for this to resolve. The
      // original one: `_buildColumn` built a *fresh* date list for its
      // `pageDates` argument whose `DateTime`s were `==`-equal but not
      // `identical()` to the ones each column's `key: dayGridKeyFor(date)`
      // was built from, and `GlobalObjectKey` compares by `identical()`,
      // so every lookup failed. `dayGridKeyFor` now memoizes one
      // `GlobalKey` per calendar day, so `==`-equal dates share a key and
      // no caller has to preserve object identity at all — which is why
      // this call passes no candidate list and simply lets the resolver
      // search whichever columns are mounted right now.
      final secondColumnCenter = tester.getCenter(find.byType(DayGrid).at(1));

      final target = resolveDragTarget(
        globalPosition: secondColumnCenter,
        settings: settings,
        slotHeight: slotHeight,
        blockDuration: const Duration(minutes: 30),
      );

      expect(
        target,
        isNotNull,
        reason:
            'resolveDragTarget should find the DayGrid column under the '
            'pointer via its memoized GlobalKey',
      );
      // Monday-first week of Wednesday 2026-09-09 starts on 2026-09-07.
      expect(target!.date, DateTime(2026, 9, 8));
    });

    testWidgets(
      'dayGridKeyFor memoizes one key per calendar day, so a rebuild with '
      'fresh DateTime instances does not reinflate every DayGrid',
      (tester) async {
        expect(
          dayGridKeyFor(DateTime(2026, 9, 9)),
          same(dayGridKeyFor(DateTime(2026, 9, 9))),
        );
        // Same calendar day, different instance and time of day.
        expect(
          dayGridKeyFor(DateTime(2026, 9, 9, 13, 45)),
          same(dayGridKeyFor(DateTime(2026, 9, 9))),
        );
        expect(
          dayGridKeyFor(DateTime(2026, 9, 10)),
          isNot(same(dayGridKeyFor(DateTime(2026, 9, 9)))),
        );
      },
    );
  });

  group('a drag that pages across a day boundary mid-gesture', () {
    testWidgets(
      'keeps tracking the pointer after the origin page unmounts, commits '
      'the move onto the new day, and stops auto-paging on release',
      (tester) async {
        // Day view (one column per page), so crossing to another day
        // requires a real page turn that unmounts the origin page — and
        // with it the dragged block's own gesture recognizers.
        _resizeViewport(tester, const Size(800, 1000));
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final today = container.read(selectedDateProvider);
        final tomorrow = DateTime(today.year, today.month, today.day + 1);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: DayScreen()),
          ),
        );
        await tester.pump();
        expect(find.byType(DayGrid), findsOneWidget);
        expect(find.text('Breakfast'), findsOneWidget);

        final grabPoint = tester.getCenter(find.text('Breakfast'));
        final gesture = await tester.startGesture(
          grabPoint,
          kind: PointerDeviceKind.mouse,
        );
        // Past the pan slop, so the drag actually starts.
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump();
        expect(container.read(dragStateProvider), isNotNull);

        // Dwell in the right edge zone until it pages to tomorrow.
        await gesture.moveTo(Offset(790, grabPoint.dy));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 650));
        // Leave the edge zone so paging stops after exactly one turn, then
        // let the page-turn animation settle — that settling is what
        // unmounts the origin page's subtree and disposes the recognizers
        // that used to own this gesture.
        await gesture.moveTo(Offset(400, grabPoint.dy));
        await tester.pumpAndSettle();

        expect(
          container.read(selectedDateProvider),
          tomorrow,
          reason: 'the edge dwell should have paged forward exactly one day',
        );

        // The drag must still be live and still tracking: before the fix,
        // the origin page's unmount silently killed the pointer route, so
        // no further move (and no pointer-up) could ever arrive again.
        // This is the first move delivered *after* that unmount.
        final dropPoint = tester.getCenter(find.byType(DayGrid));
        await gesture.moveTo(dropPoint);
        await tester.pump();

        final duringDrag = container.read(dragStateProvider);
        expect(duringDrag, isNotNull);
        expect(
          duringDrag!.targetDate,
          tomorrow,
          reason:
              'pointer moves after the page turn must resolve against the '
              'column visible now, not the page the drag started on',
        );

        // Release over the new day's column.
        await gesture.up();
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          container.read(dragStateProvider),
          isNull,
          reason: 'releasing must resolve the drag rather than leak it',
        );

        // The move really landed: gone from today, present on tomorrow.
        final originBlocks = await container.read(
          dayBlocksProvider(today).future,
        );
        expect(originBlocks.where((b) => b.title == 'Breakfast'), isEmpty);
        final targetBlocks = await container.read(
          dayBlocksProvider(tomorrow).future,
        );
        expect(targetBlocks.where((b) => b.title == 'Breakfast'), hasLength(1));

        // And auto-paging really stopped: several more dwell periods pass
        // with no further page turns.
        final pageAfterDrop = container.read(selectedDateProvider);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 650));
        }
        await tester.pumpAndSettle();
        expect(container.read(selectedDateProvider), pageAfterDrop);
      },
    );

    testWidgets('releasing where no column is under the pointer cancels the '
        'move, after the landzone previews the snap-back to its original '
        'slot', (tester) async {
      _resizeViewport(tester, const Size(800, 1000));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final today = container.read(selectedDateProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DayScreen()),
        ),
      );
      await tester.pump();

      final grabPoint = tester.getCenter(find.text('Breakfast'));
      final gesture = await tester.startGesture(
        grabPoint,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();
      expect(container.read(dragStateProvider)!.hasTarget, isTrue);

      // Up into the header, above every day column.
      await gesture.moveTo(const Offset(400, 4));
      await tester.pump();

      // No valid column is under the pointer here, so the landzone falls
      // back to previewing Breakfast's own original slot — releasing here
      // still cancels the move, this just shows where it would land.
      final dragStateOverHeader = container.read(dragStateProvider)!;
      expect(dragStateOverHeader.hasTarget, isTrue);
      expect(dragStateOverHeader.targetDate, dragStateOverHeader.originalDate);
      expect(
        dragStateOverHeader.targetStart,
        dragStateOverHeader.block.start,
      );
      expect(find.byKey(const Key('day-grid-landzone')), findsOneWidget);

      await gesture.up();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(container.read(dragStateProvider), isNull);
      final blocks = await container.read(dayBlocksProvider(today).future);
      expect(blocks.where((b) => b.title == 'Breakfast'), hasLength(1));
    });
  });
}
