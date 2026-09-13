import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/task/widgets/tag_pills.dart';

void main() {
  group('TagPills', () {
    testWidgets('renders nothing for an empty tag list', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TagPills(tags: [])),
        ),
      );

      expect(find.byType(Chip), findsNothing);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('renders a read-only Chip per tag when onRemoved is omitted', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TagPills(tags: ['home', 'errands'])),
        ),
      );

      expect(find.text('home'), findsOneWidget);
      expect(find.text('errands'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('renders removable InputChips when onRemoved is given', (
      tester,
    ) async {
      String? removed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TagPills(
              tags: const ['home'],
              onRemoved: (tag) => removed = tag,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(removed, 'home');
    });
  });
}
