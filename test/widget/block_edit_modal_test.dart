import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
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
              date: _date,
              block: block,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('BlockCategoryPlaceholder', () {
    testWidgets('renders a row of empty squares', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BlockCategoryPlaceholder()),
        ),
      );

      expect(find.byType(BlockCategoryPlaceholder), findsOneWidget);
      expect(find.byType(Container), findsWidgets);
    });
  });

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

  group('showTimeWheelPicker', () {
    testWidgets('returns the picked time on Done', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await showTimeWheelPicker(
                    context: context,
                    initial: DateTime(2026, 9, 9, 9),
                    settings: _settings,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // The wheel starts scrolled to `initial`'s hour/minute, and Done
      // confirms without any scrolling, so it must return the same value.
      expect(picked, DateTime(2026, 9, 9, 9));
    });

    testWidgets('returns null when dismissed without confirming', (
      tester,
    ) async {
      DateTime? picked = DateTime(2026, 9, 9, 9);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await showTimeWheelPicker(
                    context: context,
                    initial: DateTime(2026, 9, 9, 9),
                    settings: _settings,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      // Tap the barrier above the sheet to dismiss it without confirming.
      await tester.tapAt(const Offset(400, 50));
      await tester.pumpAndSettle();

      expect(picked, isNull);
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

    testWidgets('confirms on a second tap within the timeout', (
      tester,
    ) async {
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

    testWidgets('tapping the start row, scrolling the minute wheel and '
        'confirming updates the start', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
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
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.start, DateTime(2000, 1, 1, 9, 15));
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
      await tester.tap(find.text('Done'));
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

      final nextDayBlocks = container
          .read(dayBlocksProvider(nextDate))
          .value!;
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

      final nextDayBlocks = container
          .read(dayBlocksProvider(nextDate))
          .value!;
      expect(nextDayBlocks, hasLength(1));
      expect(nextDayBlocks.single.title, 'Deep work');
    });

    testWidgets('tapping outside the dialog does not dismiss it', (
      tester,
    ) async {
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

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
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
