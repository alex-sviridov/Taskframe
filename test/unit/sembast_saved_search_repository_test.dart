import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/saved_search/data/sembast_saved_search_repository.dart';

void main() {
  group('SembastSavedSearchRepository', () {
    late SembastSavedSearchRepository repository;
    late Database db;

    setUp(() async {
      db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastSavedSearchRepository(db);
    });

    test('load starts empty', () async {
      expect(await repository.load(), isEmpty);
    });

    test('add appends a new view with the next order', () async {
      await repository.add(name: 'Tasks view 1', query: '#urgent');
      final second = await repository.add(name: 'Tasks view 2', query: '@work');

      final views = await repository.load();
      expect(views, hasLength(2));
      expect(second.order, 1);
    });

    test('added views load back in creation order', () async {
      await repository.add(name: 'First', query: 'a');
      await repository.add(name: 'Second', query: 'b');

      final views = await repository.load();

      expect(views[0].name, 'First');
      expect(views[1].name, 'Second');
    });

    test('rename replaces the view in a later load', () async {
      final added = await repository.add(name: 'Tasks view 1', query: '#a');

      await repository.rename(added, 'Urgent');

      final views = await repository.load();
      expect(views.single.name, 'Urgent');
    });

    test('delete removes the view from a later load', () async {
      final added = await repository.add(name: 'Tasks view 1', query: '#a');

      await repository.delete(added);

      expect(await repository.load(), isEmpty);
    });

    test('reorder persists the given order', () async {
      final first = await repository.add(name: 'First', query: 'a');
      final second = await repository.add(name: 'Second', query: 'b');

      await repository.reorder([second, first]);

      final views = await repository.load();
      expect(views.map((v) => v.name), ['Second', 'First']);
    });

    test(
      'add after deleting an earlier view does not collide orders',
      () async {
        await repository.add(name: 'First', query: 'a');
        final second = await repository.add(name: 'Second', query: 'b');
        final third = await repository.add(name: 'Third', query: 'c');

        await repository.delete(
          (await repository.load()).firstWhere((v) => v.name == 'First'),
        );
        final fourth = await repository.add(name: 'Fourth', query: 'd');

        expect(fourth.order, 3);
        final orders = [second.order, third.order, fourth.order];
        expect(orders.toSet(), hasLength(orders.length));
      },
    );

    test('delete soft-deletes: view stays but is excluded from load', () async {
      final added = await repository.add(name: 'Work', query: '#work');

      await repository.delete(added);

      expect(await repository.load(), isEmpty);
      final record = await savedSearchesStore.record(added.id).get(db);
      expect(record!['deleted'], isTrue);
    });
  });
}
