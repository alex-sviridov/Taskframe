import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
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

Future<void> _pump(
  WidgetTester tester,
  TimeObject block, {
  bool showTitle = true,
  Category? category,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: BlockView(block: block, showTitle: showTitle, category: category),
    ),
  ),
);

void main() {
  group('BlockView', () {
    testWidgets('shows the block title', (tester) async {
      await _pump(tester, _block(BlockKind.anchor));

      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('hides the title when showTitle is false, keeping the box', (
      tester,
    ) async {
      await _pump(tester, _block(BlockKind.anchor), showTitle: false);

      expect(find.text('Work'), findsNothing);
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, isNotNull);
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

    testWidgets('fills with the category color for an anchor block', (
      tester,
    ) async {
      final category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
      );

      await _pump(tester, _block(BlockKind.anchor), category: category);

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF2196F3));
    });

    testWidgets('outlines with the category color for a frame block', (
      tester,
    ) async {
      final category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
      );

      await _pump(tester, _block(BlockKind.frame), category: category);

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, isNull);
      expect(decoration.border!.top.color, const Color(0xFF2196F3));
    });

    testWidgets('prefixes the title with the category emoji when it has '
        'one', (tester) async {
      final category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      await _pump(tester, _block(BlockKind.anchor), category: category);

      expect(find.text('💼 Work'), findsOneWidget);
    });

    testWidgets('shows the plain title when the category has no emoji', (
      tester,
    ) async {
      final category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
      );

      await _pump(tester, _block(BlockKind.anchor), category: category);

      expect(find.text('Work'), findsOneWidget);
    });
  });
}
