import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/category/data/sembast_category_repository.dart';
import 'package:taskframe/features/category/models/category.dart';

void main() {
  group('SembastCategoryRepository', () {
    late SembastCategoryRepository repository;
    late Database db;

    setUp(() async {
      db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastCategoryRepository(db);
    });

    test('load synthesizes the default category when the store has '
        'nothing yet', () async {
      final categories = await repository.load();

      expect(categories, hasLength(1));
      expect(categories.single.isDefault, isTrue);
    });

    test('add appends a new non-default category, after the default', () async {
      final added = await repository.add(
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      expect(added.isDefault, isFalse);
      final categories = await repository.load();
      expect(categories, hasLength(2));
      expect(categories.first.isDefault, isTrue);
      expect(categories.last.name, 'Work');
    });

    test('two added categories get distinct, non-default ids', () async {
      final first = await repository.add(name: 'Work', colorValue: 0xFF2196F3);
      final second = await repository.add(
        name: 'Health',
        colorValue: 0xFF4CAF50,
      );

      expect(first.id, isNot(second.id));
      expect(first.id, isNot(Category.defaultId));
    });

    test('added categories load back in creation order', () async {
      await repository.add(name: 'First', colorValue: 0xFF000001);
      await repository.add(name: 'Second', colorValue: 0xFF000002);

      final categories = await repository.load();

      expect(categories[1].name, 'First');
      expect(categories[2].name, 'Second');
    });

    test("update changes an added category's name, color and emoji", () async {
      final added = await repository.add(name: 'Work', colorValue: 0xFF2196F3);

      final updated = await repository.update(
        added,
        name: 'Career',
        colorValue: 0xFFFF0000,
        emoji: '🚀',
      );

      expect(updated.id, added.id);
      expect(updated.name, 'Career');
      expect(updated.colorValue, 0xFFFF0000);
      expect(updated.emoji, '🚀');
    });

    test('update leaves fields unspecified as null unchanged', () async {
      final added = await repository.add(
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      final updated = await repository.update(added, colorValue: 0xFFFF0000);

      expect(updated.name, 'Work');
      expect(updated.emoji, '💼');
    });

    test('update replaces the category in a later load', () async {
      final added = await repository.add(name: 'Work', colorValue: 0xFF2196F3);

      await repository.update(added, name: 'Career');

      final categories = await repository.load();
      expect(categories.singleWhere((c) => c.id == added.id).name, 'Career');
    });

    test(
      'updating the default category only applies the color change',
      () async {
        final defaultCategory = (await repository.load()).single;

        final updated = await repository.update(
          defaultCategory,
          name: 'Renamed',
          colorValue: 0xFFFF0000,
          emoji: '🔥',
        );

        expect(updated.name, 'Default');
        expect(updated.emoji, isNull);
        expect(updated.colorValue, 0xFFFF0000);
      },
    );

    test('delete removes an added category from a later load', () async {
      final added = await repository.add(name: 'Work', colorValue: 0xFF2196F3);

      await repository.delete(added);

      final categories = await repository.load();
      expect(categories.where((c) => c.id == added.id), isEmpty);
    });

    test('delete on the default category is a no-op', () async {
      final defaultCategory = (await repository.load()).single;

      await repository.delete(defaultCategory);

      final categories = await repository.load();
      expect(categories, hasLength(1));
      expect(categories.single.isDefault, isTrue);
    });

    test('delete soft-deletes a non-default category', () async {
      final added = await repository.add(name: 'Work', colorValue: 0xFF000000);

      await repository.delete(added);

      expect(await repository.load(), hasLength(1)); // default only
      final record = await categoriesStore.record(added.id).get(db);
      expect(record!['deleted'], isTrue);
    });
  });
}
