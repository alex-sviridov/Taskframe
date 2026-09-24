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
            onPressed: () =>
                showCategoryEditSheet(context: context, category: category),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('CategoryEditSheet', () {
    testWidgets('shows no Save/Cancel buttons', (tester) async {
      final container = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Save'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    group('create mode', () {
      testWidgets('shows no Delete action before anything is typed', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Delete'), findsNothing);
      });

      testWidgets('typing a name creates the category live, no Save needed', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Work');
        await tester.pump();

        final categories = container.read(categoryListProvider).value!;
        expect(categories.where((c) => c.name == 'Work'), hasLength(1));
      });

      testWidgets('the Delete action appears once the category is created', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Work');
        await tester.pump();

        expect(find.text('Delete'), findsOneWidget);
      });

      testWidgets('shows both a color swatch and an emoji button', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('categoryEditSheet.colorSwatch')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('categoryEditSheet.emojiButton')),
          findsOneWidget,
        );
      });

      testWidgets('picking a color before typing applies once the category is '
          'created', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('categoryEditSheet.colorSwatch')),
        );
        await tester.pumpAndSettle();
        final redSwatch = find.byWidgetPredicate(_isRedSwatch);
        await tester.tap(redSwatch);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Work');
        await tester.pump();

        final categories = container.read(categoryListProvider).value!;
        final created = categories.singleWhere((c) => c.name == 'Work');
        expect(created.colorValue, Colors.red.toARGB32());
      });

      testWidgets('symbols and spaces are stripped as they are typed, only '
          'letters, digits and "-" are kept', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Side Project #1!');
        await tester.pump();

        final categories = container.read(categoryListProvider).value!;
        expect(categories.where((c) => c.name == 'SideProject1'), hasLength(1));
      });

      testWidgets('a hyphen is kept as typed', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'side-project');
        await tester.pump();

        final categories = container.read(categoryListProvider).value!;
        expect(categories.where((c) => c.name == 'side-project'), hasLength(1));
      });

      testWidgets('typing further keystrokes updates the same category, not '
          'a new one', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        await _pumpOpenButton(tester, container);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Wor');
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Work');
        await tester.pump();

        final categories = container.read(categoryListProvider).value!;
        expect(categories.where((c) => c.name == 'Work'), hasLength(1));
      });
    });

    group('edit mode', () {
      testWidgets('pre-fills the name field with the category name', (
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

      testWidgets('typing a new name updates it live, no Save needed', (
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
        await tester.pump();

        final categories = container.read(categoryListProvider).value!;
        expect(
          categories.singleWhere((c) => c.id == created.id).name,
          'Career',
        );
      });

      testWidgets('picking a new color updates it live', (tester) async {
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

        final categories = container.read(categoryListProvider).value!;
        final updated = categories.singleWhere((c) => c.id == created.id);
        expect(updated.colorValue, Colors.red.toARGB32());
      });

      testWidgets('Delete asks for confirmation, then removes the category '
          'and closes the sheet', (tester) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        await _pumpOpenButton(tester, container, category: created);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.tap(find.text('Delete').last);
        await tester.pumpAndSettle();

        final categories = container.read(categoryListProvider).value!;
        expect(categories.where((c) => c.id == created.id), isEmpty);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Open'), findsOneWidget);
      });

      testWidgets('canceling the delete confirmation leaves the category', (
        tester,
      ) async {
        final container = await _seededContainer();
        addTearDown(container.dispose);
        final created = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        await _pumpOpenButton(tester, container, category: created);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        final categories = container.read(categoryListProvider).value!;
        expect(categories.where((c) => c.id == created.id), hasLength(1));
      });

      testWidgets(
        'on the default category: name field is disabled, no emoji button, '
        'and no Delete action',
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
          expect(find.text('Delete'), findsNothing);
        },
      );

      testWidgets(
        'on the default category: picking a color updates it live, name '
        'and emoji stay unchanged',
        (tester) async {
          final container = await _seededContainer();
          addTearDown(container.dispose);
          final categories = container.read(categoryListProvider).value!;
          final defaultCategory = categories.single;
          await _pumpOpenButton(tester, container, category: defaultCategory);

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('categoryEditSheet.colorSwatch')),
          );
          await tester.pumpAndSettle();
          final redSwatch = find.byWidgetPredicate(_isRedSwatch);
          await tester.tap(redSwatch);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Done'));
          await tester.pumpAndSettle();

          final after = container.read(categoryListProvider).value!;
          expect(after.single.name, 'Default');
          expect(after.single.emoji, isNull);
          expect(after.single.colorValue, Colors.red.toARGB32());
        },
      );
    });
  });
}
