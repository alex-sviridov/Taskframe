import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/data/category_repository.dart';
import 'package:taskframe/features/category/models/category.dart';

void main() {
  group('InMemoryCategoryRepository', () {
    late InMemoryCategoryRepository repository;

    setUp(() => repository = InMemoryCategoryRepository());

    test('load returns exactly one seeded default category', () async {
      final categories = await repository.load();

      expect(categories, hasLength(1));
      expect(categories.single.isDefault, isTrue);
    });

    test('the default category has a fixed name and no emoji', () async {
      final categories = await repository.load();

      expect(categories.single.name, 'Default');
      expect(categories.single.emoji, isNull);
    });

    test('add appends a new non-default category', () async {
      final added = await repository.add(
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      expect(added.isDefault, isFalse);
      expect(added.name, 'Work');
      expect(added.colorValue, 0xFF2196F3);
      expect(added.emoji, '💼');
    });

    test(
      'an added category shows up in a later load, after the default',
      () async {
        await repository.add(name: 'Work', colorValue: 0xFF2196F3, emoji: '💼');

        final categories = await repository.load();

        expect(categories, hasLength(2));
        expect(categories.first.isDefault, isTrue);
        expect(categories.last.name, 'Work');
      },
    );

    test('two added categories get distinct, non-default ids', () async {
      final first = await repository.add(name: 'Work', colorValue: 0xFF2196F3);
      final second = await repository.add(
        name: 'Health',
        colorValue: 0xFF4CAF50,
      );

      expect(first.id, isNot(equals(second.id)));
      expect(first.id, isNot(Category.defaultId));
      expect(second.id, isNot(Category.defaultId));
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
  });
}
