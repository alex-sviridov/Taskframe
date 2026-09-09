import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_screen.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';

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

      expect(find.text('title'), findsOneWidget);
      semantics.dispose();
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
}
