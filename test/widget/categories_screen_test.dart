import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/categories_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: CategoriesScreen())),
  );
  await tester.pump();
}

void main() {
  group('CategoriesScreen', () {
    testWidgets('shows the default category first, with no delete icon', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Default'), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsNothing);
    });

    testWidgets('the add-category action has an accessible tooltip', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byTooltip('Add category'), findsOneWidget);
    });

    testWidgets('a category row uses its own color as its background', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pump();

      final card = tester.widget<Container>(
        find.ancestor(of: find.text('Work'), matching: find.byType(Container)),
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF2196F3));
    });

    testWidgets(
      'adding a category via the app bar action shows it in the list',
      (tester) async {
        await _pump(tester);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Work');
        await tester.pump();
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(find.text('Work'), findsOneWidget);
      },
    );

    testWidgets('tapping a non-default category row opens it in edit mode', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Career');
      await tester.pump();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Career'), findsOneWidget);
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('deleting a category happens from inside its edit sheet, with '
        'confirmation', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsNothing);
    });
  });
}
