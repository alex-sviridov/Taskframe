// test/unit/saved_search_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/saved_search/data/saved_search_repository.dart';

void main() {
  group('InMemorySavedSearchRepository', () {
    test('load starts empty', () async {
      final repository = InMemorySavedSearchRepository();

      expect(await repository.load(), isEmpty);
    });

    test('add appends a new view with the next order', () async {
      final repository = InMemorySavedSearchRepository();

      await repository.add(name: 'Tasks view 1', query: '#urgent');
      final second = await repository.add(name: 'Tasks view 2', query: '@work');

      final views = await repository.load();
      expect(views, hasLength(2));
      expect(second.order, 1);
    });

    test('two added views get distinct ids', () async {
      final repository = InMemorySavedSearchRepository();

      final first = await repository.add(name: 'A', query: 'a');
      final second = await repository.add(name: 'B', query: 'b');

      expect(first.id, isNot(second.id));
    });

    test('rename updates the name and persists it', () async {
      final repository = InMemorySavedSearchRepository();
      final added = await repository.add(name: 'Tasks view 1', query: '#a');

      final renamed = await repository.rename(added, 'Urgent');

      expect(renamed.name, 'Urgent');
      final views = await repository.load();
      expect(views.single.name, 'Urgent');
    });

    test('delete removes the view', () async {
      final repository = InMemorySavedSearchRepository();
      final added = await repository.add(name: 'Tasks view 1', query: '#a');

      await repository.delete(added);

      expect(await repository.load(), isEmpty);
    });

    test(
      'reorder persists the given order and reassigns order fields',
      () async {
        final repository = InMemorySavedSearchRepository();
        final first = await repository.add(name: 'First', query: 'a');
        final second = await repository.add(name: 'Second', query: 'b');

        await repository.reorder([second, first]);

        final views = await repository.load();
        expect(views.map((v) => v.name), ['Second', 'First']);
        expect(views.map((v) => v.order), [0, 1]);
      },
    );

    test(
      'add after deleting an earlier view does not collide orders',
      () async {
        final repository = InMemorySavedSearchRepository();
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
  });
}
