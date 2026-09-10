import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
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
}
