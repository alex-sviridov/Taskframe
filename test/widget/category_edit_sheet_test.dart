import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_edit_sheet.dart';

bool _isRedSwatch(Widget widget) =>
    widget is Container &&
    widget.decoration is BoxDecoration &&
    (widget.decoration! as BoxDecoration).color == Colors.red;

Future<ProviderContainer> _seededContainer() async {
  final container = ProviderContainer();
  await container.read(categoryListProvider.future);
  return container;
}

Future<void> _pumpOpenButton(
  WidgetTester tester,
  ProviderContainer container, {
  Category? category,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCategoryEditSheet(
              context: context,
              category: category,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('CategoryEditSheet', () {
    testWidgets('create mode: entering a name and saving adds a category', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Work');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final categories = container.read(categoryListProvider).value!;
      expect(categories.where((c) => c.name == 'Work'), hasLength(1));
    });

    testWidgets('create mode: Save is disabled while the name is empty', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('create mode: shows both a color swatch and an emoji button', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('categoryEditSheet.colorSwatch')), findsOneWidget);
      expect(find.byKey(const Key('categoryEditSheet.emojiButton')), findsOneWidget);
    });

    testWidgets('edit mode: pre-fills the name field with the category name', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      await _pumpOpenButton(tester, container, category: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('edit mode: changing the name and saving persists it', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      final created = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
      await _pumpOpenButton(tester, container, category: created);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Career');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final categories = container.read(categoryListProvider).value!;
      expect(categories.singleWhere((c) => c.id == created.id).name, 'Career');
    });

    testWidgets(
      'edit mode on the default category: name field is disabled and no '
      'emoji button is shown',
      (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final categories = container.read(categoryListProvider).value!;
        final defaultCategory = categories.single;
        await _pumpOpenButton(tester, container, category: defaultCategory);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final nameField = tester.widget<TextField>(find.byType(TextField));
        expect(nameField.enabled, isFalse);
        expect(
          find.byKey(const Key('categoryEditSheet.emojiButton')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('categoryEditSheet.colorSwatch')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'edit mode on the default category: saving only persists the color',
      (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final categories = container.read(categoryListProvider).value!;
        final defaultCategory = categories.single;
        await _pumpOpenButton(tester, container, category: defaultCategory);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final after = container.read(categoryListProvider).value!;
        expect(after.single.name, 'Default');
        expect(after.single.emoji, isNull);
      },
    );

    testWidgets('Cancel dismisses the sheet without saving changes', (
      tester,
    ) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Work');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final categories = container.read(categoryListProvider).value!;
      expect(categories.where((c) => c.name == 'Work'), isEmpty);
    });

    testWidgets(
      'color picker: picking a new color and saving persists it',
      (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
        await _pumpOpenButton(tester, container, category: created);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('categoryEditSheet.colorSwatch')),
        );
        await tester.pumpAndSettle();

        final redSwatch = find.byWidgetPredicate(_isRedSwatch);
        expect(redSwatch, findsOneWidget);
        await tester.tap(redSwatch);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final categories = container.read(categoryListProvider).value!;
        final updated = categories.singleWhere((c) => c.id == created.id);
        expect(updated.colorValue, Colors.red.toARGB32());
      },
    );
  });
}
