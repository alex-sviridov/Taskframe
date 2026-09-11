import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/date_key.dart';
import 'package:taskframe/core/storage/first_run_seed.dart';
import 'package:taskframe/features/category/models/category.dart';

void main() {
  group('seedIfEmpty', () {
    test('writes the default category when categories is empty', () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');

      await seedIfEmpty(db);

      final records = await categoriesStore.find(db);
      expect(records, hasLength(1));
      expect(records.single.key, Category.defaultId);
      expect(records.single.value['name'], 'Default');
    });

    test('writes five seed blocks for today when day_blocks is empty', () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');

      await seedIfEmpty(db);

      final records = await dayBlocksStore.find(db);
      expect(records, hasLength(5));
      final todayKey = dateKeyFor(DateTime.now());
      expect(records.every((r) => r.value['dateKey'] == todayKey), isTrue);
    });

    test('does not duplicate seed blocks on a second call', () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');

      await seedIfEmpty(db);
      await seedIfEmpty(db);

      expect(await dayBlocksStore.count(db), 5);
    });

    test('does not overwrite an existing category', () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      const existing = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
      );
      await categoriesStore.record(existing.id).put(db, existing.toMap());

      await seedIfEmpty(db);

      final records = await categoriesStore.find(db);
      expect(records, hasLength(1));
      expect(records.single.key, 'category-1');
    });
  });
}
