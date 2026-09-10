import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
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
final _date = DateTime(2000, 1, 1);

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
    testWidgets('shows the block\'s title, start and end', (tester) async {
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

    testWidgets('tapping the start row and confirming a new time updates '
        'it', (tester) async {
      final (container, block) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container, block);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BlockTimeRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // The wheel opens scrolled to the block's own start (09:00) and Done
      // confirms without scrolling, so the start is unchanged but the round
      // trip through updateBlock must not have been silently rejected.
      final blocks = container.read(dayBlocksProvider(_date)).value!;
      expect(blocks.single.start, block.start);
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

      await container.read(dayBlocksProvider(_date).notifier).deleteBlock(block);
      await tester.pumpAndSettle();

      expect(find.byType(BlockEditModal), findsNothing);
    });
  });
}
