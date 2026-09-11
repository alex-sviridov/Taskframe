import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/data/category_repository.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';

void main() {
  group('categoryById', () {
    const categories = [
      Category(id: Category.defaultId, name: 'Default', colorValue: 0xFF009688),
      Category(id: 'category-1', name: 'Work', colorValue: 0xFF2196F3),
    ];

    test('returns the category with the matching id', () {
      expect(categoryById(categories, 'category-1').id, 'category-1');
    });

    test('falls back to the default category when the id matches none', () {
      expect(
        categoryById(categories, 'deleted-category').id,
        Category.defaultId,
      );
    });
  });

  group('categoryListProvider', () {
    test('loads the repository categories', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final categories = await container.read(categoryListProvider.future);
      final expected = await InMemoryCategoryRepository().load();

      expect(categories.map((c) => c.id), expected.map((c) => c.id));
    });

    test(
      'addCategory appends the new category returned by the repository',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(categoryListProvider.future);

        await container
            .read(categoryListProvider.notifier)
            .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');

        final categories = container.read(categoryListProvider).value!;
        expect(categories.where((c) => c.name == 'Work'), hasLength(1));
      },
    );

    test('addCategory returns the created category', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);

      final created = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');

      expect(created.name, 'Work');
      expect(created.emoji, '💼');
    });

    test('updateCategory persists a name/color/emoji change', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      final created = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3);

      await container
          .read(categoryListProvider.notifier)
          .updateCategory(created, name: 'Career', colorValue: 0xFFFF0000);

      final categories = container.read(categoryListProvider).value!;
      final updated = categories.singleWhere((c) => c.id == created.id);
      expect(updated.name, 'Career');
      expect(updated.colorValue, 0xFFFF0000);
    });

    test('deleteCategory removes the category from state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(categoryListProvider.future);
      final created = await container
          .read(categoryListProvider.notifier)
          .addCategory(name: 'Work', colorValue: 0xFF2196F3);

      await container
          .read(categoryListProvider.notifier)
          .deleteCategory(created);

      final categories = container.read(categoryListProvider).value!;
      expect(categories.where((c) => c.id == created.id), isEmpty);
    });

    test('deleteCategory on the default category leaves it in state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final categories = await container.read(categoryListProvider.future);
      final defaultCategory = categories.single;

      await container
          .read(categoryListProvider.notifier)
          .deleteCategory(defaultCategory);

      final after = container.read(categoryListProvider).value!;
      expect(after, hasLength(1));
      expect(after.single.isDefault, isTrue);
    });
  });
}
