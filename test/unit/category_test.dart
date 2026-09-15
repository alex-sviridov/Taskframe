import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';

void main() {
  group('Category', () {
    test('isDefault is true when id equals Category.defaultId', () {
      final category = Category(
        id: Category.defaultId,
        name: 'Default',
        colorValue: 0xFF009688,
      );

      expect(category.isDefault, isTrue);
    });

    test('isDefault is false for any other id', () {
      final category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      expect(category.isDefault, isFalse);
    });

    test('copyWith replaces only the given fields', () {
      final category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      final updated = category.copyWith(name: 'Career', colorValue: 0xFFFF0000);

      expect(updated.id, 'category-1');
      expect(updated.name, 'Career');
      expect(updated.colorValue, 0xFFFF0000);
      expect(updated.emoji, '💼');
    });

    test('formatTitle prefixes the emoji when the category has one', () {
      final category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      expect(category.formatTitle('Deep work'), '💼 Deep work');
    });

    test('formatTitle returns the title unchanged when the category has no '
        'emoji', () {
      final category = Category(
        id: Category.defaultId,
        name: 'Default',
        colorValue: 0xFF009688,
      );

      expect(category.formatTitle('Deep work'), 'Deep work');
    });

    test('copyWith with no arguments returns equivalent fields', () {
      final category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      final copy = category.copyWith();

      expect(copy.id, category.id);
      expect(copy.name, category.name);
      expect(copy.colorValue, category.colorValue);
      expect(copy.emoji, category.emoji);
    });
  });

  group('toMap/fromMap', () {
    test('fromMap(toMap()) round-trips every field', () {
      final category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      final restored = Category.fromMap(category.toMap());

      expect(restored.id, category.id);
      expect(restored.name, category.name);
      expect(restored.colorValue, category.colorValue);
      expect(restored.emoji, category.emoji);
    });

    test('fromMap restores a null emoji', () {
      final category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
      );

      expect(Category.fromMap(category.toMap()).emoji, isNull);
    });

    test('toMap/fromMap round-trip updatedAt and deleted', () {
      final updatedAt = DateTime.utc(2026, 9, 15, 12);
      final category = Category(
        id: 'c1',
        name: 'Work',
        colorValue: 0xFF000000,
        updatedAt: updatedAt,
        deleted: true,
      );
      final restored = Category.fromMap(category.toMap());
      expect(restored.updatedAt, updatedAt);
      expect(restored.deleted, isTrue);
    });
  });
}
