import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/category/models/category.dart';

void main() {
  group('Category', () {
    test('isDefault is true when id equals Category.defaultId', () {
      const category = Category(
        id: Category.defaultId,
        name: 'Default',
        colorValue: 0xFF009688,
      );

      expect(category.isDefault, isTrue);
    });

    test('isDefault is false for any other id', () {
      const category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      expect(category.isDefault, isFalse);
    });

    test('copyWith replaces only the given fields', () {
      const category = Category(
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
      const category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      expect(category.formatTitle('Deep work'), '💼 Deep work');
    });

    test('formatTitle returns the title unchanged when the category has no '
        'emoji', () {
      const category = Category(
        id: Category.defaultId,
        name: 'Default',
        colorValue: 0xFF009688,
      );

      expect(category.formatTitle('Deep work'), 'Deep work');
    });

    test('copyWith with no arguments returns equivalent fields', () {
      const category = Category(
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
}
