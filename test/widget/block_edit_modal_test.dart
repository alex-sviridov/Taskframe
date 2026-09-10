import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';

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
}
