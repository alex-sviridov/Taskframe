import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_picker.dart';
import 'package:taskframe/features/day/date_format.dart';
import 'package:taskframe/features/day/day_blocks_provider.dart';
import 'package:taskframe/features/day/day_schedule_block_actions.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);

// Fixed, far-past date: InMemoryDayBlocksRepository seeds hardcoded blocks
// for whatever date happens to be the real wall-clock "today", so tests
// must never risk a date (or a date+1 next-day computation) coinciding
// with it. Matches the convention already established in
// test/unit/resize_state_provider_test.dart.
final _date = DateTime(2000);

/// Seeds a fresh container with one block on [_date] and returns both the
/// container and the block exactly as the repository assigned it (in
/// particular, its real generated id). [BlockEditModal] looks up the live
/// block from the provider by [TimeObject.id] every rebuild — passing it a
/// [TimeObject] whose id doesn't match anything in that provider's list
/// would make the modal think the block was deleted and close itself
/// immediately, so every test opens the modal with this returned block,
/// never a hand-built one.
Future<(ProviderContainer, TimeObject)> _seededContainer() async {
  final container = ProviderContainer();
  await container.read(dayBlocksProvider(_date).future);
  final block = await container
      .read(dayBlocksProvider(_date).notifier)
      .addBlock(
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
        title: 'Work',
      );
  return (container, block);
}

Future<void> _pumpOpenButton(
  WidgetTester tester,
  ProviderContainer container,
  TimeObject block,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showBlockEditModal(
              context: context,
              column: DayColumn(_date),
              actions: dayScheduleBlockActions,
              block: block,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

/// Sets the test surface to a narrow (mobile) width for the duration of
/// the current test, matching the convention already used for the modal's
/// own bottom-sheet-vs-dialog tests.
void _useNarrowView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('BlockTimeRow', () {
    testWidgets('shows the label and formatted time', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockTimeRow(
              label: 'Starts',
              time: DateTime(2026, 9, 9, 9, 5),
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Starts'), findsOneWidget);
      expect(find.text('09:05'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockTimeRow(
              label: 'Starts',
              time: DateTime(2026, 9, 9, 9),
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(BlockTimeRow));

      expect(tapped, isTrue);
    });
  });

  group('BlockTimeDropdown', () {
    Future<void> pump(
      WidgetTester tester, {
      required String label,
      required DateTime value,
      required ({DateTime start, DateTime end}) range,
      required ValueChanged<DateTime> onChanged,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockTimeDropdown(
            label: label,
            value: value,
            range: range,
            onChanged: onChanged,
          ),
        ),
      ),
    );

    testWidgets('shows the label and the current time formatted as HH:mm', (
      tester,
    ) async {
      await pump(
        tester,
        label: 'Starts',
        value: DateTime(2026, 9, 9, 9),
        range: (start: DateTime(2026, 9, 9, 6), end: DateTime(2026, 9, 9, 12)),
        onChanged: (_) {},
      );

      expect(find.text('Starts'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
    });

    testWidgets('lists only the quarter-hour marks within range', (
      tester,
    ) async {
      await pump(
        tester,
        label: 'Starts',
        value: DateTime(2026, 9, 9, 9),
        range: (
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 9, 30),
        ),
        onChanged: (_) {},
      );

      await tester.tap(find.byType(DropdownButtonFormField<DateTime>));
      await tester.pumpAndSettle();

      expect(find.text('09:00'), findsWidgets);
      expect(find.text('09:15'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);
      expect(find.text('09:45'), findsNothing);
    });

    testWidgets('selecting a time calls onChanged with it', (tester) async {
      DateTime? picked;
      await pump(
        tester,
        label: 'Starts',
        value: DateTime(2026, 9, 9, 9),
        range: (
          start: DateTime(2026, 9, 9, 9),
          end: DateTime(2026, 9, 9, 9, 30),
        ),
        onChanged: (value) => picked = value,
      );

      await tester.tap(find.byType(DropdownButtonFormField<DateTime>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('09:15').last);
      await tester.pumpAndSettle();

      expect(picked, DateTime(2026, 9, 9, 9, 15));
    });
  });

  group('BlockDeleteButton', () {
    testWidgets('does not confirm on a single tap', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockDeleteButton(onConfirmed: () => confirmed = true),
          ),
        ),
      );

      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();

      expect(confirmed, isFalse);
    });

    testWidgets('confirms on a second tap within the timeout', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockDeleteButton(onConfirmed: () => confirmed = true),
          ),
        ),
      );

      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();
      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();

      expect(confirmed, isTrue);
    });

    testWidgets('reverts to needing two taps again after the timeout '
        'lapses', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockDeleteButton(onConfirmed: () => confirmed = true),
          ),
        ),
      );

      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();

      expect(confirmed, isFalse);
    });
  });

  group('BlockEditModal', () {
    testWidgets('the close button sits above the title field', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final closeTop = tester.getTopLeft(find.byIcon(Icons.close)).dy;
      final titleTop = tester.getTopLeft(find.byType(TextField)).dy;
      expect(closeTop, lessThan(titleTop));
    });

    testWidgets('the title field shows a visible underline, signaling '
        "it's editable", (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.border, isA<UnderlineInputBorder>());
    });

    testWidgets('a freshly created block (empty title) autofocuses the '
        'title field', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(dayBlocksProvider(_date).future);
      final block = await container
          .read(dayBlocksProvider(_date).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 9),
            end: DateTime(2000, 1, 1, 9, 30),
            kind: BlockKind.anchor,
            title: '',
          );
      await _pumpOpenButton(tester, container, block);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
    });

    testWidgets('an existing block with a title does not autofocus the '
        'title field', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isFalse);
    });

    testWidgets("shows the block's title, start and end", (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);
    });

    testWidgets('on a wide width, picking a time from the Starts dropdown '
        'persists it immediately', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockTimeDropdown).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('09:15').last);
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.start, DateTime(2000, 1, 1, 9, 15));
    });

    testWidgets('shows a bottom sheet on a narrow width', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('shows a centered dialog on a wide width', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('editing the title persists it via the provider', (
      tester,
    ) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Deep work');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.title, 'Deep work');
    });

    testWidgets('clearing the title resets the field to the current title '
        'instead of persisting a blank one', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.title, 'Work');
    });

    testWidgets('deleting the block while an uncommitted title edit is '
        'focused does not resurrect it', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Focus and edit the title but never submit or blur it — deleting
      // the block below must pop (and unfocus) before any late blur-commit
      // can call updateBlock on the now-deleted block.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Deep work');

      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();
      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks, isEmpty);

      // The notifier's own cached state can't show a resurrection (its
      // update-in-place loop only replaces an id it still holds), so also
      // force a fresh load straight from the repository — this is what
      // actually surfaces a late blur-commit's "promote as if seeded"
      // write landing after the delete.
      container.invalidate(dayBlocksProvider(_date));
      final reloaded = await container.read(dayBlocksProvider(_date).future);
      expect(reloaded, isEmpty);
    });

    testWidgets('tapping the start row and scrolling the minute wheel '
        'updates the start immediately, with no separate confirm step', (
      tester,
    ) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      _useNarrowView(tester);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockTimeRow).first);
      await tester.pumpAndSettle();
      // The minute wheel opens on the block's own start minute (00, index
      // 0) with a 40px itemExtent; dragging it up by exactly one item
      // moves the selection to 15 without touching the hour wheel.
      await tester.drag(
        find.byType(ListWheelScrollView).at(1),
        const Offset(0, -40),
      );
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.start, DateTime(2000, 1, 1, 9, 15));
      // Applying a value on every scroll tick must not also collapse the
      // picker — only tapping the row again does that.
      expect(find.byType(ListWheelScrollView), findsWidgets);
    });

    testWidgets('an edit that would overlap another block is silently '
        'rejected', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      // Touches (but doesn't overlap) the block's own 09:00-09:30 span, so
      // it's only in the way once the end below moves to 09:45.
      await container
          .read(dayBlocksProvider(_date).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 9, 30),
            end: DateTime(2000, 1, 1, 10),
            kind: BlockKind.anchor,
          );
      _useNarrowView(tester);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockTimeRow).last);
      await tester.pumpAndSettle();
      // The minute wheel opens on the block's own end minute (30, index
      // 2); dragging it up by one item moves the selection to 45, making
      // the block span 09:00-09:45 — overlapping the 09:30-10:00 block
      // just added.
      await tester.drag(
        find.byType(ListWheelScrollView).at(1),
        const Offset(0, -40),
      );
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      final updated = blocks.firstWhere((b) => b.id == block.id);
      expect(updated.end, block.end);
    });

    testWidgets('the copy button is disabled when the next day is busy at '
        'the same time', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      final nextDate = DateTime(2000, 1, 2);
      await container.read(dayBlocksProvider(nextDate).future);
      await container
          .read(dayBlocksProvider(nextDate).notifier)
          .addBlock(
            start: block.start.add(const Duration(days: 1)),
            end: block.end.add(const Duration(days: 1)),
            kind: BlockKind.anchor,
          );
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.content_copy),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the copy button is enabled and copies when the next day '
        'is free', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      final nextDate = DateTime(2000, 1, 2);
      await container.read(dayBlocksProvider(nextDate).future);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.content_copy));
      await tester.pumpAndSettle();

      final nextDayBlocks = container.read(dayBlocksProvider(nextDate)).value!;
      expect(nextDayBlocks, hasLength(1));
      expect(nextDayBlocks.single.title, 'Work');
    });

    testWidgets('an uncommitted title edit is committed before copying to '
        'the next day', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      final nextDate = DateTime(2000, 1, 2);
      await container.read(dayBlocksProvider(nextDate).future);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Type a new title but never submit it or otherwise blur the field
      // before tapping copy.
      await tester.enterText(find.byType(TextField), 'Deep work');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.content_copy));
      await tester.pumpAndSettle();

      final nextDayBlocks = container.read(dayBlocksProvider(nextDate)).value!;
      expect(nextDayBlocks, hasLength(1));
      expect(nextDayBlocks.single.title, 'Deep work');
    });

    testWidgets('tapping outside the dialog dismisses it', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);

      // Tap a point clearly on the barrier, outside the centered dialog.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets("shows the block's date", (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('01/01/2000'), findsOneWidget);
    });

    testWidgets("picking a different date moves the block to that date's "
        'provider', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();
      // The Material date picker defaults to a calendar grid; "15" is
      // always a valid day in every month, so this reliably picks the
      // 15th of whatever month the picker opened on.
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final oldDateBlocks = container.read(dayBlocksProvider(_date)).value!;
      expect(oldDateBlocks.where((b) => b.id == block.id), isEmpty);

      final newDate = DateTime(_date.year, _date.month, 15);
      final newDateBlocks = await container.read(
        dayBlocksProvider(newDate).future,
      );
      expect(newDateBlocks.where((b) => b.id == block.id), hasLength(1));
    });

    testWidgets('picking a different date closes only the calendar, '
        'leaving the modal open and showing the new date', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byType(BlockEditModal), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      final newDate = DateTime(_date.year, _date.month, 15);
      expect(
        find.text(formatDate(newDate, _settings.dateFormat)),
        findsOneWidget,
      );
    });

    testWidgets('the hour wheel only offers hours reachable within the gap '
        "next to the block's nearest neighbor", (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      // "Work" runs 09:00-09:30; adding this makes 08:30 the nearest
      // previous block boundary, so editing Starts can only reach
      // 08:30-09:15 (bounded above by Work's own end minus the 15-minute
      // minimum duration) — hours 8 and 9 only.
      await container
          .read(dayBlocksProvider(_date).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 8),
            end: DateTime(2000, 1, 1, 8, 30),
            kind: BlockKind.anchor,
          );
      _useNarrowView(tester);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockTimeRow).first);
      await tester.pumpAndSettle();

      final hourWheel = tester.widget<ListWheelScrollView>(
        find.byType(ListWheelScrollView).first,
      );
      expect(hourWheel.childDelegate.estimatedChildCount, 2);
    });

    testWidgets('the minute wheel only offers quarters valid for the '
        'currently selected hour', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await container
          .read(dayBlocksProvider(_date).notifier)
          .addBlock(
            start: DateTime(2000, 1, 1, 8),
            end: DateTime(2000, 1, 1, 8, 30),
            kind: BlockKind.anchor,
          );
      _useNarrowView(tester);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockTimeRow).first);
      await tester.pumpAndSettle();

      // Work starts at 09:00, so the minute wheel opens on hour 9, whose
      // only valid quarters (within 08:30-09:15) are :00 and :15.
      final minuteWheel = tester.widget<ListWheelScrollView>(
        find.byType(ListWheelScrollView).at(1),
      );
      expect(minuteWheel.childDelegate.estimatedChildCount, 2);
    });

    testWidgets('the centered wheel value is styled bolder than the rest', (
      tester,
    ) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      _useNarrowView(tester);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockTimeRow).first);
      await tester.pumpAndSettle();

      // Work starts at 09:00 — "09" is the centered hour; "08" is a
      // different, non-centered one the wheel's limited visible range
      // still renders alongside it.
      final selected = tester.widget<Text>(find.text('09').first);
      final unselected = tester.widget<Text>(find.text('08').first);
      expect(selected.style?.fontWeight, FontWeight.bold);
      expect(unselected.style?.fontWeight, isNot(FontWeight.bold));
    });

    testWidgets('tapping the start row expands the wheel picker inline '
        'instead of opening a bottom sheet', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      _useNarrowView(tester);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // The modal itself is a bottom sheet on a narrow width, so this
      // checks that count doesn't grow — the wheel picker never opens a
      // second, separate one of its own.
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tap(find.byType(BlockTimeRow).first);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(ListWheelScrollView), findsWidgets);
    });

    testWidgets('tapping the same row again collapses the picker without '
        'changing the time', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      _useNarrowView(tester);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockTimeRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BlockTimeRow).first);
      await tester.pumpAndSettle();

      expect(find.byType(ListWheelScrollView), findsNothing);
      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.start, block.start);
    });

    testWidgets("opening the end row's picker collapses an already-open "
        'start picker', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      _useNarrowView(tester);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockTimeRow).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(BlockTimeRow).last);
      await tester.tap(find.byType(BlockTimeRow).last);
      await tester.pumpAndSettle();

      // Only one field's wheels (hour + minute) should be showing at once.
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));
    });

    testWidgets('shows a category picker and selecting an option persists '
        'the category change', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      final work = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(BlockCategoryPicker), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work').last);
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.categoryId, work.id);
    });

    testWidgets('shows a segmented type selector with the current kind '
        'selected', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final segmented = tester.widget<SegmentedButton<BlockKind>>(
        find.byType(SegmentedButton<BlockKind>),
      );
      expect(segmented.selected, {BlockKind.anchor});
    });

    testWidgets('selecting Frame in the type selector persists the kind '
        'change', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Frame'));
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.kind, BlockKind.frame);
    });

    testWidgets('confirming delete twice removes the block and closes', (
      tester,
    ) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pump();
      await tester.tap(find.byType(BlockDeleteButton));
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks, isEmpty);
      expect(find.byType(BlockEditModal), findsNothing);
    });

    testWidgets('closes itself if the block is deleted elsewhere while '
        'open', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await container
          .read(dayBlocksProvider(_date).notifier)
          .deleteBlock(block);
      await tester.pumpAndSettle();

      expect(find.byType(BlockEditModal), findsNothing);
    });
  });
}
