import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/category/widgets/category_picker.dart';

Future<void> _pumpPicker(
  WidgetTester tester,
  ProviderContainer container, {
  required String selectedCategoryId,
  required ValueChanged<String> onSelected,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: BlockCategoryPicker(
          selectedCategoryId: selectedCategoryId,
          onSelected: onSelected,
        ),
      ),
    ),
  ),
);

void _useNarrowView(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('BlockCategoryPicker', () {
    group('on a wide width', () {
      testWidgets('shows a labeled dropdown field listing every loaded '
          'category', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: Category.defaultId,
          onSelected: (_) {},
        );
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        expect(find.text('Category'), findsOneWidget);

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        expect(find.text('💼 Work'), findsWidgets);
      });

      testWidgets('selecting an item in the dropdown calls onSelected with '
          'its category id', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        final work = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        String? selected;
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: Category.defaultId,
          onSelected: (id) => selected = id,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Work').last);
        await tester.pumpAndSettle();

        expect(selected, work.id);
      });

      testWidgets('the closed field shows a swatch of the selected '
          "category's color, not a full-color background", (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        final work = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: work.id,
          onSelected: (_) {},
        );
        await tester.pumpAndSettle();

        final swatch = tester.widget<CircleAvatar>(
          find
              .descendant(
                of: find.byType(DropdownButtonFormField<String>),
                matching: find.byType(CircleAvatar),
              )
              .first,
        );
        expect(swatch.backgroundColor, const Color(0xFF2196F3));
      });
    });

    group('on a narrow width', () {
      testWidgets('shows a labeled field with the selected category '
          'instead of a dropdown', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        final work = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');
        _useNarrowView(tester);
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: work.id,
          onSelected: (_) {},
        );
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.text('Category'), findsOneWidget);
        expect(find.text('💼 Work'), findsOneWidget);
      });

      testWidgets('tapping the chip opens a wheel picker listing every '
          'category', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        _useNarrowView(tester);
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: Category.defaultId,
          onSelected: (_) {},
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Default'));
        await tester.pumpAndSettle();

        expect(find.byType(CupertinoPicker), findsOneWidget);
        expect(find.text('Work'), findsOneWidget);
      });

      testWidgets('settling the wheel on a new category calls onSelected '
          'with its id, with no separate confirm step', (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);
        final work = await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3);
        String? selected;
        _useNarrowView(tester);
        await _pumpPicker(
          tester,
          container,
          selectedCategoryId: Category.defaultId,
          onSelected: (id) => selected = id,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Default'));
        await tester.pumpAndSettle();
        // Default is the wheel's first (index 0) entry, Work its second;
        // dragging up by one 48px item settles the wheel on Work.
        await tester.drag(find.byType(CupertinoPicker), const Offset(0, -48));
        await tester.pumpAndSettle();

        expect(selected, work.id);
        // No Done/confirm button anywhere in the sheet.
        expect(find.byType(TextButton), findsNothing);
      });
    });
  });
}
