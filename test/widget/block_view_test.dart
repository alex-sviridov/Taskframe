import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/block_view.dart';

TimeObject _block(BlockKind kind) => TimeObject(
  id: '1',
  title: 'Work',
  start: DateTime(2026, 9, 9, 9),
  end: DateTime(2026, 9, 9, 13),
  kind: kind,
  locked: false,
);

Future<void> _pump(WidgetTester tester, TimeObject block) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: BlockView(block: block)),
  ),
);

void main() {
  group('BlockView', () {
    testWidgets('shows the block title', (tester) async {
      await _pump(tester, _block(BlockKind.anchor));

      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('fills the container for an anchor block', (tester) async {
      await _pump(tester, _block(BlockKind.anchor));

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;

      expect(decoration.color, isNotNull);
    });

    testWidgets('only outlines the container for a frame block', (
      tester,
    ) async {
      await _pump(tester, _block(BlockKind.frame));

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;

      expect(decoration.color, isNull);
      expect(decoration.border, isNotNull);
    });
  });
}
