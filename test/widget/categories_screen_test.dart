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

    testWidgets(
      'adding a category via the app bar action shows it in the list',
      (tester) async {
        await _pump(tester);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Work');
        await tester.tap(find.text('Save'));
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
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Career'), findsOneWidget);
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('deleting a non-default category asks for confirmation', (
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

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('confirming the delete dialog removes the category', (
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

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsNothing);
    });

    testWidgets('canceling the delete dialog leaves the category', (
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

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
    });
  });
}
