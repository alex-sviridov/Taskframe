# Responsive Week View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the schedule screen show a full 7-day week on wide viewports (≥900px) instead of a single day, sharing the existing day-grid rendering and paging/gesture code between both modes, and lay down hardcoded (not-yet-user-editable) `firstDayOfWeek` and `dateFormat` settings.

**Architecture:** `DayScreen` becomes generic over how many days one page covers (`daysPerPage`, computed from viewport width via `LayoutBuilder`), instead of splitting into separate day/week screens. Each page (`_SchedulePage`) lays out `daysPerPage` day columns in a `Row`, reusing the existing `DayGrid` per column unchanged except for a new `showHourLabels` flag; week mode adds one shared `HourGutter` widget instead of each column drawing its own hour labels. Date formatting becomes pattern-driven instead of hardcoded English text.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`), existing `PageView`/`PageController` finger-tracked paging, Playwright for e2e.

**Spec:** `docs/superpowers/specs/2026-09-09-responsive-week-view-design.md`

## Global Constraints

- Week breakpoint: viewport width `>= 900.0` logical pixels shows 7 days per page; below it, 1 day per page.
- `firstDayOfWeek` defaults to `DateTime.monday`; `dateFormat` defaults to `'dd/MM/yyyy'` (European). Both are hardcoded provider values — no settings screen, no persistence.
- Swiping/paging in week mode moves by a whole week (7 days) per page, using the same `PageController`/finger-tracked-drag mechanism as day mode.
- Week-mode column headers omit the weekday name; day-mode headers keep it.
- In week mode, hour labels (e.g. "6:00") are drawn once in a shared left gutter, not repeated per day column; grid lines still belong to each day column.
- No new user-facing settings UI and no `shared_preferences` (or any) persistence dependency in this plan.

---

### Task 1: Extend `DaySettings` with `firstDayOfWeek` and `dateFormat`

**Files:**
- Modify: `lib/features/day/day_settings.dart`
- Modify: `test/unit/day_settings_test.dart`
- Modify: `test/widget/day_grid_test.dart:7` (the `_settings` const needs the two new required fields to keep compiling)

**Interfaces:**
- Produces: `DaySettings` gains two new required fields — `final int firstDayOfWeek;` and `final String dateFormat;` — consumed by Tasks 2, 4, and 5.

- [ ] **Step 1: Write the failing test**

Replace the contents of `test/unit/day_settings_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';

void main() {
  test(
    'daySettingsProvider defaults to a 6-23 day, Monday-first, European dates',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final settings = container.read(daySettingsProvider);

      expect(settings.dayStartHour, 6);
      expect(settings.dayEndHour, 23);
      expect(settings.firstDayOfWeek, DateTime.monday);
      expect(settings.dateFormat, 'dd/MM/yyyy');
    },
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/day_settings_test.dart`
Expected: FAIL — `firstDayOfWeek`/`dateFormat` are not defined on `DaySettings`, or `DaySettings(...)` rejects the missing-in-old-signature call (compile error).

- [ ] **Step 3: Implement `DaySettings`**

Replace the contents of `lib/features/day/day_settings.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configures the visible range and layout of the day/week schedule.
///
/// Hardcoded for now; a future settings screen can let the user override
/// [daySettingsProvider] without the grid/screen needing to change.
class DaySettings {
  /// Creates a [DaySettings].
  const new({
    required this.dayStartHour,
    required this.dayEndHour,
    required this.firstDayOfWeek,
    required this.dateFormat,
  });

  /// The first hour shown on the grid (inclusive).
  final int dayStartHour;

  /// The last hour shown on the grid (inclusive).
  final int dayEndHour;

  /// The weekday (`DateTime.monday`..`DateTime.sunday`) a week starts on,
  /// in week view.
  final int firstDayOfWeek;

  /// A date-format pattern using `dd`/`MM`/`yyyy` tokens, e.g.
  /// `'dd/MM/yyyy'` (European) or `'MM/dd/yyyy'` (US). See `formatDate`.
  final String dateFormat;
}

/// The day/week schedule's hardcoded layout settings.
final daySettingsProvider = Provider<DaySettings>(
  (ref) => const DaySettings(
    dayStartHour: 6,
    dayEndHour: 23,
    firstDayOfWeek: DateTime.monday,
    dateFormat: 'dd/MM/yyyy',
  ),
);
```

- [ ] **Step 4: Fix the now-broken `DayGrid` widget test fixture**

In `test/widget/day_grid_test.dart`, replace line 7:

```dart
const _settings = DaySettings(dayStartHour: 6, dayEndHour: 23);
```

with:

```dart
const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);
```

- [ ] **Step 5: Run the full test suite to verify it passes**

Run: `flutter test`
Expected: PASS (all tests, including `day_settings_test.dart` and `day_grid_test.dart`)

- [ ] **Step 6: Commit**

```bash
git add lib/features/day/day_settings.dart test/unit/day_settings_test.dart test/widget/day_grid_test.dart
git commit -m "$(cat <<'EOF'
Add firstDayOfWeek and dateFormat to DaySettings

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

---

### Task 2: Pattern-based date formatting

**Files:**
- Modify: `lib/features/day/date_format.dart`
- Modify: `lib/features/day/day_screen.dart:215-218` (single call site, updated to compile against the new function — the surrounding paging logic is restructured later in Task 5)
- Create: `test/unit/date_format_test.dart`

**Interfaces:**
- Consumes: none new.
- Produces: `String formatDate(DateTime date, String pattern)` and `String formatDayHeaderLabel(DateTime date, {required bool showWeekday, required String pattern})`, both consumed by Task 5.

- [ ] **Step 1: Write the failing test**

Create `test/unit/date_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/date_format.dart';

void main() {
  group('formatDate', () {
    test('formats using a European dd/MM/yyyy pattern', () {
      final date = DateTime(2026, 9, 9);

      expect(formatDate(date, 'dd/MM/yyyy'), '09/09/2026');
    });

    test('formats using a US MM/dd/yyyy pattern', () {
      final date = DateTime(2026, 12, 3);

      expect(formatDate(date, 'MM/dd/yyyy'), '12/03/2026');
    });
  });

  group('formatDayHeaderLabel', () {
    test('includes the weekday name when showWeekday is true', () {
      final date = DateTime(2026, 9, 9); // a Wednesday

      expect(
        formatDayHeaderLabel(date, showWeekday: true, pattern: 'dd/MM/yyyy'),
        'Wednesday, 09/09/2026',
      );
    });

    test('omits the weekday name when showWeekday is false', () {
      final date = DateTime(2026, 9, 9);

      expect(
        formatDayHeaderLabel(date, showWeekday: false, pattern: 'dd/MM/yyyy'),
        '09/09/2026',
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/date_format_test.dart`
Expected: FAIL — `formatDate`/`formatDayHeaderLabel` are not defined.

- [ ] **Step 3: Implement the formatters**

Replace the contents of `lib/features/day/date_format.dart`:

```dart
const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Formats [date] using [pattern], a template built from the tokens `dd`
/// (zero-padded day), `MM` (zero-padded month), and `yyyy` (4-digit year),
/// e.g. `'dd/MM/yyyy'` or `'MM/dd/yyyy'`.
String formatDate(DateTime date, String pattern) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');

  return pattern
      .replaceAll('dd', day)
      .replaceAll('MM', month)
      .replaceAll('yyyy', year);
}

/// Formats [date] for a schedule header: with its weekday name prefixed
/// (e.g. `"Wednesday, 09/09/2026"`) when [showWeekday] is true, or just the
/// formatted date (e.g. `"09/09/2026"`) when it's false.
String formatDayHeaderLabel(
  DateTime date, {
  required bool showWeekday,
  required String pattern,
}) {
  final formatted = formatDate(date, pattern);
  if (!showWeekday) return formatted;

  final weekday = _weekdays[date.weekday - 1];
  return '$weekday, $formatted';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/date_format_test.dart`
Expected: PASS

- [ ] **Step 5: Update the call site in `day_screen.dart`**

In `lib/features/day/day_screen.dart`, replace (around line 210-221):

```dart
    return Column(
      children: [
        SizedBox(
          height: _headerHeight,
          child: Center(
            child: Text(
              key: const Key('day-screen-date-label'),
              formatDayLabel(date),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
```

with:

```dart
    return Column(
      children: [
        SizedBox(
          height: _headerHeight,
          child: Center(
            child: Text(
              key: const Key('day-screen-date-label'),
              formatDayHeaderLabel(
                date,
                showWeekday: true,
                pattern: settings.dateFormat,
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
```

(`settings` is already in scope from `final settings = ref.watch(daySettingsProvider);` earlier in this build method.)

- [ ] **Step 6: Run the full test suite to verify it passes**

Run: `flutter test`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/features/day/date_format.dart lib/features/day/day_screen.dart test/unit/date_format_test.dart
git commit -m "$(cat <<'EOF'
Replace hardcoded date label with pattern-based formatting

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

---

### Task 3: `startOfWeek` helper

**Files:**
- Create: `lib/features/day/week_utils.dart`
- Create: `test/unit/week_utils_test.dart`

**Interfaces:**
- Consumes: none new.
- Produces: `DateTime startOfWeek(DateTime date, {required int firstDayOfWeek})`, consumed by Task 5.

- [ ] **Step 1: Write the failing test**

Create `test/unit/week_utils_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/week_utils.dart';

void main() {
  group('startOfWeek', () {
    test('returns the Monday of a Monday-first week containing a Wednesday', () {
      final wednesday = DateTime(2026, 9, 9);

      final start = startOfWeek(wednesday, firstDayOfWeek: DateTime.monday);

      expect(start, DateTime(2026, 9, 7));
    });

    test('returns the same date when it already is the first day', () {
      final monday = DateTime(2026, 9, 7);

      final start = startOfWeek(monday, firstDayOfWeek: DateTime.monday);

      expect(start, DateTime(2026, 9, 7));
    });

    test('supports a Sunday-first week', () {
      final wednesday = DateTime(2026, 9, 9);

      final start = startOfWeek(wednesday, firstDayOfWeek: DateTime.sunday);

      expect(start, DateTime(2026, 9, 6));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/week_utils_test.dart`
Expected: FAIL — `package:taskframe/features/day/week_utils.dart` does not exist.

- [ ] **Step 3: Implement `startOfWeek`**

Create `lib/features/day/week_utils.dart`:

```dart
/// Returns the start (midnight) of the calendar week containing [date],
/// treating [firstDayOfWeek] (`DateTime.monday`..`DateTime.sunday`) as the
/// first day of that week.
DateTime startOfWeek(DateTime date, {required int firstDayOfWeek}) {
  final offset = (date.weekday - firstDayOfWeek + 7) % 7;
  final start = date.subtract(Duration(days: offset));
  return DateTime(start.year, start.month, start.day);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/week_utils_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/week_utils.dart test/unit/week_utils_test.dart
git commit -m "$(cat <<'EOF'
Add startOfWeek helper for week-aligned paging

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

---

### Task 4: `DayGrid.showHourLabels` and the shared `HourGutter`

**Files:**
- Modify: `lib/features/day/widgets/day_grid.dart`
- Modify: `test/widget/day_grid_test.dart`
- Create: `lib/features/day/widgets/hour_gutter.dart`
- Create: `test/widget/hour_gutter_test.dart`

**Interfaces:**
- Consumes: `DaySettings` (Task 1).
- Produces: `DayGrid` gains `this.showHourLabels = true` (optional, backward compatible); `HourGutter` widget with `static const double width = 48.0` and constructor `HourGutter({required DaySettings settings, required double slotHeight})`. Both consumed by Task 5.

- [ ] **Step 1: Write the failing `DayGrid` test**

In `test/widget/day_grid_test.dart`, add this test inside `group('DayGrid', ...)`, after the `'uses whatever slotHeight it is given'` test:

```dart
    testWidgets('positions a block flush left when hour labels are hidden', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayGrid(
              date: _date,
              blocks: [_workBlock],
              settings: _settings,
              slotHeight: _slotHeight,
              showHourLabels: false,
              onCreateBlock: ({required start, required end, required kind}) {},
            ),
          ),
        ),
      );

      final positioned = tester.widget<Positioned>(
        find.ancestor(of: find.text('Work'), matching: find.byType(Positioned)),
      );

      expect(positioned.left, 4);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/day_grid_test.dart`
Expected: FAIL — `showHourLabels` is not a parameter of `DayGrid`.

- [ ] **Step 3: Add `showHourLabels` to `DayGrid`**

In `lib/features/day/widgets/day_grid.dart`, replace the constructor (lines 16-27):

```dart
  const new({
    required this.date,
    required this.blocks,
    required this.settings,
    required this.slotHeight,
    required this.onCreateBlock,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
    this.onSwipeCancel,
    super.key,
  });
```

with:

```dart
  const new({
    required this.date,
    required this.blocks,
    required this.settings,
    required this.slotHeight,
    required this.onCreateBlock,
    this.showHourLabels = true,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
    this.onSwipeCancel,
    super.key,
  });
```

Then, after the `slotHeight` field (lines 38-39):

```dart
  /// Pixel height of a single 15-minute slot.
  final double slotHeight;
```

add:

```dart
  /// Pixel height of a single 15-minute slot.
  final double slotHeight;

  /// Whether this grid draws its own hour-label gutter on the left.
  ///
  /// `false` in week view, where a single `HourGutter` draws the labels
  /// once for all day columns; this grid still draws its own horizontal
  /// gridlines regardless.
  final bool showHourLabels;
```

Then, in `_DayGridState`, after the `_dayStartInMinutes` getter (around line 73):

```dart
  double get _dayStartInMinutes => widget.settings.dayStartHour * 60;
```

add:

```dart
  double get _dayStartInMinutes => widget.settings.dayStartHour * 60;

  double get _gridLeft => widget.showHourLabels ? 48 : 4;
```

Then replace the two hardcoded `left: 48,` occurrences (the block `Positioned` around line 147 and the draft-overlay `Positioned` around line 156) with `left: _gridLeft,`.

Then replace the painter construction (lines 134-140):

```dart
                painter: _DayGridPainter(
                  settings: widget.settings,
                  slotHeight: widget.slotHeight,
                  lineColor: scheme.outlineVariant,
                  labelStyle: Theme.of(context).textTheme.labelSmall,
                ),
```

with:

```dart
                painter: _DayGridPainter(
                  settings: widget.settings,
                  slotHeight: widget.slotHeight,
                  lineColor: scheme.outlineVariant,
                  labelStyle: Theme.of(context).textTheme.labelSmall,
                  gridLeft: _gridLeft,
                  showLabels: widget.showHourLabels,
                ),
```

Then replace the `_DayGridPainter` class (lines 296-354) entirely:

```dart
class _DayGridPainter extends CustomPainter {
  const new({
    required this.settings,
    required this.slotHeight,
    required this.lineColor,
    required this.labelStyle,
    required this.gridLeft,
    required this.showLabels,
  });

  final DaySettings settings;
  final double slotHeight;
  final Color lineColor;
  final TextStyle? labelStyle;
  final double gridLeft;
  final bool showLabels;

  static const double _labelLeft = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final hourPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5;
    final quarterPaint = Paint()
      ..color = lineColor.withValues(alpha: lineColor.a * 0.5)
      ..strokeWidth = 1;

    final totalHours = settings.dayEndHour - settings.dayStartHour;
    for (var hour = 0; hour <= totalHours; hour++) {
      final y = hour * 4 * slotHeight;
      canvas.drawLine(Offset(gridLeft, y), Offset(size.width, y), hourPaint);

      if (hour < totalHours) {
        for (var quarter = 1; quarter < 4; quarter++) {
          final qy = y + quarter * slotHeight;
          canvas.drawLine(
            Offset(gridLeft, qy),
            Offset(size.width, qy),
            quarterPaint,
          );
        }
      }

      if (!showLabels) continue;

      final labelHour = settings.dayStartHour + hour;
      if (labelHour.isEven) {
        final painter = TextPainter(
          text: TextSpan(text: '$labelHour:00', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(_labelLeft, y - painter.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DayGridPainter oldDelegate) =>
      oldDelegate.settings != settings ||
      oldDelegate.slotHeight != slotHeight ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.gridLeft != gridLeft ||
      oldDelegate.showLabels != showLabels;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/day_grid_test.dart`
Expected: PASS (all tests, including the new one)

- [ ] **Step 5: Write the failing `HourGutter` test**

Create `test/widget/hour_gutter_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/widgets/hour_gutter.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);

void main() {
  testWidgets(
    'HourGutter sizes itself to span day-start through day-end',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HourGutter(settings: _settings, slotHeight: 16),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);

      // 6:00 to 23:00 is 17 hours = 68 slots.
      expect(sizedBox.height, 68 * 16.0);
      expect(sizedBox.width, HourGutter.width);
    },
  );
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/widget/hour_gutter_test.dart`
Expected: FAIL — `package:taskframe/features/day/widgets/hour_gutter.dart` does not exist.

- [ ] **Step 7: Implement `HourGutter`**

Create `lib/features/day/widgets/hour_gutter.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:taskframe/features/day/day_settings.dart';

/// The hour-label column shown once, to the left of every day column, when
/// multiple days share one page (week view). Draws only the hour labels
/// that `DayGrid` would otherwise draw itself in single-day mode.
class HourGutter extends StatelessWidget {
  const new({required this.settings, required this.slotHeight, super.key});

  /// Matches `DayGrid`'s own label-gutter width, so day columns' grid
  /// lines still start at the same x whether or not they draw their own
  /// labels.
  static const double width = 48.0;

  final DaySettings settings;
  final double slotHeight;

  @override
  Widget build(BuildContext context) {
    final slotCount = (settings.dayEndHour - settings.dayStartHour) * 4;
    return SizedBox(
      width: width,
      height: slotCount * slotHeight,
      child: CustomPaint(
        painter: _HourGutterPainter(
          settings: settings,
          slotHeight: slotHeight,
          labelStyle: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

class _HourGutterPainter extends CustomPainter {
  const new({
    required this.settings,
    required this.slotHeight,
    required this.labelStyle,
  });

  final DaySettings settings;
  final double slotHeight;
  final TextStyle? labelStyle;

  static const double _labelLeft = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final totalHours = settings.dayEndHour - settings.dayStartHour;
    for (var hour = 0; hour <= totalHours; hour++) {
      final labelHour = settings.dayStartHour + hour;
      if (!labelHour.isEven) continue;

      final y = hour * 4 * slotHeight;
      final painter = TextPainter(
        text: TextSpan(text: '$labelHour:00', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(_labelLeft, y - painter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _HourGutterPainter oldDelegate) =>
      oldDelegate.settings != settings ||
      oldDelegate.slotHeight != slotHeight ||
      oldDelegate.labelStyle != labelStyle;
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/widget/hour_gutter_test.dart`
Expected: PASS

- [ ] **Step 9: Run the full test suite**

Run: `flutter test`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
git add lib/features/day/widgets/day_grid.dart lib/features/day/widgets/hour_gutter.dart test/widget/day_grid_test.dart test/widget/hour_gutter_test.dart
git commit -m "$(cat <<'EOF'
Let DayGrid hide its hour labels for a shared week-view gutter

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

---

### Task 5: Responsive day/week paging in `DayScreen`

**Files:**
- Modify: `lib/features/day/day_screen.dart` (full rewrite of paging/layout logic)
- Modify: `test/widget/day_screen_test.dart`

**Interfaces:**
- Consumes: `formatDayHeaderLabel` (Task 2), `startOfWeek` (Task 3), `DayGrid.showHourLabels` and `HourGutter` (Task 4), `DaySettings.firstDayOfWeek`/`dateFormat` (Task 1).
- Produces: `DayScreen` (public widget, unchanged public API — still `const DayScreen({super.key})`).

- [ ] **Step 1: Pin the existing day-mode tests to a narrow viewport**

In `test/widget/day_screen_test.dart`, add `_resizeViewport(tester, const Size(800, 1000));` as the first line inside each of these six `testWidgets` bodies (before their call to `await _pump(tester);`), so they keep exercising day mode regardless of the test runner's default surface size:

- `"shows the app title and today's hardcoded blocks"`
- `'the next-day arrow switches to a day with no blocks'`
- `"the previous-day arrow returns to today's blocks"`
- `'the date label updates when switching days'`
- `'double-tapping free space and confirming adds a new block'`
- `'a horizontal fling on free grid space switches the day'`

For example, the first becomes:

```dart
    testWidgets("shows the app title and today's hardcoded blocks", (
      tester,
    ) async {
      _resizeViewport(tester, const Size(800, 1000));
      await _pump(tester);

      expect(find.widgetWithText(AppBar, 'Day Frame'), findsOneWidget);
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });
```

Apply the same one-line addition to the other five tests listed above. The two tests that already call `_resizeViewport` with their own size (`'grows the grid slot height...'` and `'clamps the grid slot height...'`) are unchanged — their existing sizes (800x5000, 800x300) are already narrower than the 900px breakpoint.

- [ ] **Step 2: Add the failing week-view tests**

Add these three tests inside `group('DayScreen', ...)` in `test/widget/day_screen_test.dart`, after the existing tests. They need `providers.dart`'s `selectedDateProvider`, so add this import at the top of the file:

```dart
import 'package:taskframe/features/day/providers.dart';
```

```dart
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
```

- [ ] **Step 3: Run tests to verify the new ones fail**

Run: `flutter test test/widget/day_screen_test.dart`
Expected: The pre-existing tests still PASS; the three new week-view tests FAIL (only 1 `DayGrid` is ever shown; the `'day-screen-date-label-...'` key never exists).

- [ ] **Step 4: Rewrite `day_screen.dart`**

Replace the entire contents of `lib/features/day/day_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/date_format.dart';
import 'package:taskframe/features/day/day_grid_sizing.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/week_utils.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/hour_gutter.dart';

/// Below this, a 15-minute slot stops being visually distinct, so the grid
/// scrolls instead of shrinking further.
const _minSlotHeight = 8.0;

/// Half the page-index range paged over by [_DayScreenState._pageController],
/// centered on the date shown when the screen first builds. Gives roughly
/// 270 years of swiping in either direction.
const _pageSpread = 100000;

const _pageAnimationDuration = Duration(milliseconds: 250);
const Curve _pageAnimationCurve = Curves.easeOut;

/// Height of the date header row, shared by the fixed switch arrows and
/// each page's date label(s) so they stay vertically aligned.
const _headerHeight = 56.0;

/// Width of the fade strip behind each switch arrow, wide enough to fully
/// obscure the sliding date label before it reaches the arrow.
const _edgeFadeWidth = 72.0;

/// Viewport width at/above which the schedule shows a full week (7 days)
/// per page instead of a single day.
const _weekBreakpoint = 900.0;

int _daysPerPageFor(double width) => width >= _weekBreakpoint ? 7 : 1;

/// The schedule screen: a date header above a 15-minute grid of the day's
/// (or week's) blocks, paged with a finger-tracked slide animation.
///
/// Below [_weekBreakpoint] it shows one day per page; at or above it, a
/// full week per page.
class DayScreen extends ConsumerStatefulWidget {
  /// Creates a [DayScreen].
  const new({super.key});

  @override
  ConsumerState<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends ConsumerState<DayScreen> {
  late PageController _pageController;
  late DateTime _anchorDate;
  int? _daysPerPage;
  Drag? _drag;
  bool _resyncScheduled = false;

  @override
  void initState() {
    super.initState();
    _anchorDate = ref.read(selectedDateProvider);
    _pageController = PageController(initialPage: _pageSpread);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_daysPerPage != null) return;

    _daysPerPage = _daysPerPageFor(MediaQuery.sizeOf(context).width);
    if (_daysPerPage == 7) {
      _anchorDate = startOfWeek(
        _anchorDate,
        firstDayOfWeek: ref.read(daySettingsProvider).firstDayOfWeek,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _startDateForPage(int page) =>
      _anchorDate.add(Duration(days: (page - _pageSpread) * _daysPerPage!));

  void _onPageChanged(int page) {
    ref.read(selectedDateProvider.notifier).date = _startDateForPage(page);
  }

  Future<void> _animateBy(int units) async {
    final page = (_pageController.page ?? _pageController.initialPage)
        .round();
    await _pageController.animateToPage(
      page + units,
      duration: _pageAnimationDuration,
      curve: _pageAnimationCurve,
    );
  }

  void _onSwipeStart(DragStartDetails details) {
    _drag = _pageController.position.drag(details, () => _drag = null);
  }

  void _onSwipeUpdate(DragUpdateDetails details) => _drag?.update(details);

  void _onSwipeEnd(DragEndDetails details) {
    _drag?.end(details);
    _drag = null;
  }

  void _onSwipeCancel() {
    _drag?.cancel();
    _drag = null;
  }

  /// Rebuilds [_pageController] anchored to a fresh start date matching
  /// [newDaysPerPage], keeping the currently selected date visible. Called
  /// when the viewport crosses [_weekBreakpoint] and the meaning of "one
  /// page" changes between a day and a week.
  void _resyncForDaysPerPage(int newDaysPerPage) {
    final selected = ref.read(selectedDateProvider);
    final newAnchor = newDaysPerPage == 7
        ? startOfWeek(
            selected,
            firstDayOfWeek: ref.read(daySettingsProvider).firstDayOfWeek,
          )
        : selected;

    _pageController.dispose();
    setState(() {
      _daysPerPage = newDaysPerPage;
      _anchorDate = newAnchor;
      _pageController = PageController(initialPage: _pageSpread);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(daySettingsProvider);
    final daysPerPage = _daysPerPage!;

    return Scaffold(
      appBar: AppBar(title: const Text('Day Frame')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wantedDaysPerPage = _daysPerPageFor(constraints.maxWidth);
          if (wantedDaysPerPage != daysPerPage && !_resyncScheduled) {
            _resyncScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _resyncScheduled = false;
              _resyncForDaysPerPage(wantedDaysPerPage);
            });
          }

          return Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                // Disables PageView's own gesture recognizer (so it never
                // competes for drags that start on a block) while keeping
                // PageScrollPhysics' snap-to-page ballistic simulation for
                // drags forwarded manually from DayGrid's own detector —
                // see _onSwipeStart/_onSwipeEnd.
                physics: const NeverScrollableScrollPhysics(
                  parent: PageScrollPhysics(),
                ),
                onPageChanged: _onPageChanged,
                itemBuilder: (context, page) => _SchedulePage(
                  startDate: _startDateForPage(page),
                  dayCount: daysPerPage,
                  settings: settings,
                  onSwipeStart: _onSwipeStart,
                  onSwipeUpdate: _onSwipeUpdate,
                  onSwipeEnd: _onSwipeEnd,
                  onSwipeCancel: _onSwipeCancel,
                ),
              ),
              // Fades the sliding date label(s) to the background color
              // before they reach either arrow, so they never visibly
              // overlap one.
              const Positioned(
                top: 0,
                left: 0,
                width: _edgeFadeWidth,
                height: _headerHeight,
                child: IgnorePointer(child: _EdgeFade(alignLeft: true)),
              ),
              const Positioned(
                top: 0,
                right: 0,
                width: _edgeFadeWidth,
                height: _headerHeight,
                child: IgnorePointer(child: _EdgeFade(alignLeft: false)),
              ),
              // Fixed in place (outside the PageView) so only the page
              // content slides.
              Positioned(
                top: 0,
                left: 8,
                height: _headerHeight,
                child: IconButton(
                  tooltip: daysPerPage == 7 ? 'Previous week' : 'Previous day',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => unawaited(_animateBy(-1)),
                ),
              ),
              Positioned(
                top: 0,
                right: 8,
                height: _headerHeight,
                child: IconButton(
                  tooltip: daysPerPage == 7 ? 'Next week' : 'Next day',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => unawaited(_animateBy(1)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A gradient strip fading from transparent to the scaffold's background
/// color, from the header's center-ward side toward the [alignLeft] or
/// right screen edge, masking the sliding date label near a switch arrow.
class _EdgeFade extends StatelessWidget {
  const new({required this.alignLeft});

  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: alignLeft ? Alignment.centerRight : Alignment.centerLeft,
          end: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
          colors: [background.withValues(alpha: 0), background],
        ),
      ),
    );
  }
}

/// One page of [DayScreen]: [dayCount] day columns (1 in day view, 7 in
/// week view) starting at [startDate], each with its own date header and
/// [DayGrid].
///
/// The switch arrows are drawn separately, fixed in place outside the
/// [PageView] this is built by.
class _SchedulePage extends ConsumerWidget {
  const new({
    required this.startDate,
    required this.dayCount,
    required this.settings,
    required this.onSwipeStart,
    required this.onSwipeUpdate,
    required this.onSwipeEnd,
    required this.onSwipeCancel,
  });

  final DateTime startDate;
  final int dayCount;
  final DaySettings settings;
  final GestureDragStartCallback onSwipeStart;
  final GestureDragUpdateCallback onSwipeUpdate;
  final GestureDragEndCallback onSwipeEnd;
  final VoidCallback onSwipeCancel;

  bool get _showHourLabels => dayCount == 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = List.generate(
      dayCount,
      (i) => startDate.add(Duration(days: i)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          SizedBox(
            height: _headerHeight,
            child: Row(
              children: [
                if (!_showHourLabels)
                  const SizedBox(width: HourGutter.width),
                for (final date in dates)
                  Expanded(
                    child: Center(
                      child: Text(
                        key: dayCount == 1
                            ? const Key('day-screen-date-label')
                            : Key(
                                'day-screen-date-label-'
                                '${date.toIso8601String()}',
                              ),
                        formatDayHeaderLabel(
                          date,
                          showWeekday: dayCount == 1,
                          pattern: settings.dateFormat,
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slotCount =
                    (settings.dayEndHour - settings.dayStartHour) * 4;
                final slotHeight = resolveSlotHeight(
                  availableHeight: constraints.maxHeight,
                  slotCount: slotCount,
                  minSlotHeight: _minSlotHeight,
                );

                return SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_showHourLabels)
                        HourGutter(settings: settings, slotHeight: slotHeight),
                      for (final date in dates)
                        _buildColumn(ref, date, slotHeight),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn(WidgetRef ref, DateTime date, double slotHeight) {
    final blocksAsync = ref.watch(dayBlocksProvider(date));

    return Expanded(
      child: blocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load: $error')),
        data: (blocks) => DayGrid(
          date: date,
          blocks: blocks,
          settings: settings,
          slotHeight: slotHeight,
          showHourLabels: _showHourLabels,
          onSwipeStart: onSwipeStart,
          onSwipeUpdate: onSwipeUpdate,
          onSwipeEnd: onSwipeEnd,
          onSwipeCancel: onSwipeCancel,
          onCreateBlock: ({required start, required end, required kind}) {
            unawaited(
              ref
                  .read(dayBlocksProvider(date).notifier)
                  .addBlock(start: start, end: end, kind: kind),
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the widget test file to verify it passes**

Run: `flutter test test/widget/day_screen_test.dart`
Expected: PASS (all tests, including the three new week-view tests)

- [ ] **Step 6: Run the full test suite**

Run: `flutter test`
Expected: PASS

- [ ] **Step 7: Manually verify in a browser (per the `run` skill / dev-server workflow)**

Run the app (`flutter run -d web-server` or the project's usual dev command), then:
- At a narrow window width (< 900px), confirm a single day is shown with weekday name in the header and swiping/arrows move by one day.
- At a wide window width (>= 900px), confirm all 7 days of the week are shown, each with a date-only header (no weekday name), one shared hour-label gutter on the left, and the arrows/swipe move by a whole week.
- Resize the browser window across the 900px boundary and confirm the currently visible date stays visible across the switch.

Note: per the `flutter_web_server_stale_build` memory, verify the served JS is a fresh build (check the build log or file mtime) before trusting what's rendered — `flutter run -d web-server --release` can serve a stale bundle while still compiling.

- [ ] **Step 8: Commit**

```bash
git add lib/features/day/day_screen.dart test/widget/day_screen_test.dart
git commit -m "$(cat <<'EOF'
Show a full week on wide viewports, reusing day-view paging

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```

---

### Task 6: Fix e2e viewport assumptions and add week-view coverage

**Files:**
- Modify: `e2e/tests/day-screen.spec.ts`
- Modify: `e2e/tests/day-add-event.spec.ts`
- Create: `e2e/tests/week-view.spec.ts`

**Interfaces:**
- Consumes: the running app from Task 5 (tooltips `'Next day'`/`'Previous day'`/`'Next week'`/`'Previous week'`, date labels matching `dd/MM/yyyy`).
- Produces: none (leaf task).

- [ ] **Step 1: Pin `day-screen.spec.ts` to a narrow viewport and update its date-format assertion**

In `e2e/tests/day-screen.spec.ts`, add a `test.use` block right after the imports, and update the date-label regex (which changed from `"Wednesday, September 9, 2026"` style to `"Wednesday, 09/09/2026"` style):

Replace:

```ts
import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';

test.beforeEach(async ({ page }) => {
```

with:

```ts
import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';

test.use({ viewport: { width: 800, height: 900 } });

test.beforeEach(async ({ page }) => {
```

Replace:

```ts
test('the date label updates when switching days', async ({ page }) => {
  const dateLabel = page.getByText(/^\w+day, \w+ \d{1,2}, \d{4}$/);
  const before = await dateLabel.textContent();
```

with:

```ts
test('the date label updates when switching days', async ({ page }) => {
  const dateLabel = page.getByText(/^\w+day, \d{2}\/\d{2}\/\d{4}$/);
  const before = await dateLabel.textContent();
```

- [ ] **Step 2: Pin `day-add-event.spec.ts` to the same narrow viewport**

In `e2e/tests/day-add-event.spec.ts`, add the same `test.use` block after the imports:

Replace:

```ts
import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { doubleClickFreeSpace } from './support/gestures';

// (300, 650) lands in the evening, after the hardcoded Cleaning block
```

with:

```ts
import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';
import { doubleClickFreeSpace } from './support/gestures';

test.use({ viewport: { width: 800, height: 900 } });

// (300, 650) lands in the evening, after the hardcoded Cleaning block
```

- [ ] **Step 3: Create the week-view e2e spec**

Create `e2e/tests/week-view.spec.ts`:

```ts
import { test, expect } from '@playwright/test';
import { enableFlutterAccessibility } from './support/accessibility';

test.use({ viewport: { width: 1200, height: 800 } });

test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await enableFlutterAccessibility(page);
});

test('shows a full week of day headers on a wide viewport', async ({
  page,
}) => {
  await expect(page.getByText('Breakfast')).toBeVisible();

  const dateLabels = page.getByText(/^\d{2}\/\d{2}\/\d{4}$/);
  await expect(dateLabels).toHaveCount(7);
});

test('the next-week arrow advances all seven dates by a week', async ({
  page,
}) => {
  const dateLabels = page.getByText(/^\d{2}\/\d{2}\/\d{4}$/);
  const before = await dateLabels.allTextContents();

  await page.getByRole('button', { name: 'Next week' }).click();

  await expect(async () => {
    const after = await dateLabels.allTextContents();
    expect(after).not.toEqual(before);
  }).toPass();
});
```

- [ ] **Step 4: Run the e2e suite**

Run: `npm --prefix e2e test` (or the project's documented e2e command — check `e2e/package.json`/CI config if this differs)
Expected: PASS — all specs in `e2e/tests/`, including the new `week-view.spec.ts`.

- [ ] **Step 5: Commit**

```bash
git add e2e/tests/day-screen.spec.ts e2e/tests/day-add-event.spec.ts e2e/tests/week-view.spec.ts
git commit -m "$(cat <<'EOF'
Pin day-view e2e specs to a narrow viewport, add week-view e2e coverage

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_018GjJJbKXZUqqKSvbC4apm4
EOF
)"
```
