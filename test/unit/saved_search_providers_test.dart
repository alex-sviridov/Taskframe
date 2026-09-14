import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/saved_search/providers.dart';

void main() {
  group('savedSearchListProvider', () {
    test('starts empty', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final views = await container.read(savedSearchListProvider.future);

      expect(views, isEmpty);
    });

    test('addView creates "Tasks view 1" for the first view', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(savedSearchListProvider.future);

      final added = await container
          .read(savedSearchListProvider.notifier)
          .addView('#urgent');

      expect(added.name, 'Tasks view 1');
      expect(added.query, '#urgent');
    });

    test('addView numbers the second view "Tasks view 2"', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(savedSearchListProvider.future);
      await container.read(savedSearchListProvider.notifier).addView('#a');

      final second = await container
          .read(savedSearchListProvider.notifier)
          .addView('#b');

      expect(second.name, 'Tasks view 2');
    });

    test('renameView updates the name in state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(savedSearchListProvider.future);
      final added = await container
          .read(savedSearchListProvider.notifier)
          .addView('#a');

      await container
          .read(savedSearchListProvider.notifier)
          .renameView(added, 'Urgent');

      final views = container.read(savedSearchListProvider).value!;
      expect(views.single.name, 'Urgent');
    });

    test('deleteView removes the view from state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(savedSearchListProvider.future);
      final added = await container
          .read(savedSearchListProvider.notifier)
          .addView('#a');

      await container
          .read(savedSearchListProvider.notifier)
          .deleteView(added);

      final views = container.read(savedSearchListProvider).value!;
      expect(views, isEmpty);
    });

    test('reorder moves a view to its new index', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(savedSearchListProvider.future);
      await container.read(savedSearchListProvider.notifier).addView('#a');
      await container.read(savedSearchListProvider.notifier).addView('#b');

      await container.read(savedSearchListProvider.notifier).reorder(0, 2);

      final views = container.read(savedSearchListProvider).value!;
      expect(views.map((v) => v.query), ['#b', '#a']);
    });
  });
}
