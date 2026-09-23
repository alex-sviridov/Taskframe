// test/widget/swipe_action_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/widgets/swipe_action_card.dart';

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onSwipeLeft,
  VoidCallback? onSwipeRight,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SwipeActionCard(
        onSwipeLeft: onSwipeLeft,
        onSwipeRight: onSwipeRight,
        child: const SizedBox(height: 48, child: Text('Card')),
      ),
    ),
  ),
);

void main() {
  group('SwipeActionCard', () {
    testWidgets('calls onSwipeRight when dragged right past the threshold', (
      tester,
    ) async {
      var rightCalls = 0;
      await _pump(tester, onSwipeRight: () => rightCalls++);

      await tester.drag(find.text('Card'), const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(rightCalls, 1);
    });

    testWidgets('calls onSwipeLeft when dragged left past the threshold', (
      tester,
    ) async {
      var leftCalls = 0;
      await _pump(tester, onSwipeLeft: () => leftCalls++);

      await tester.drag(find.text('Card'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(leftCalls, 1);
    });

    testWidgets(
      'does not trigger either callback when the drag stays under the '
      'threshold',
      (tester) async {
        var leftCalls = 0;
        var rightCalls = 0;
        await _pump(
          tester,
          onSwipeLeft: () => leftCalls++,
          onSwipeRight: () => rightCalls++,
        );

        await tester.drag(find.text('Card'), const Offset(20, 0));
        await tester.pumpAndSettle();

        expect(leftCalls, 0);
        expect(rightCalls, 0);
      },
    );

    testWidgets('a null onSwipeRight disables the rightward swipe entirely', (
      tester,
    ) async {
      var leftCalls = 0;
      await _pump(tester, onSwipeLeft: () => leftCalls++);

      await tester.drag(find.text('Card'), const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(leftCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a null onSwipeLeft disables the leftward swipe entirely', (
      tester,
    ) async {
      var rightCalls = 0;
      await _pump(tester, onSwipeRight: () => rightCalls++);

      await tester.drag(find.text('Card'), const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(rightCalls, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
