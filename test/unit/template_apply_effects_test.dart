import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/template_apply_effects.dart';

void main() {
  final date = DateTime(2026, 9, 14);

  group('templateApplyEffectsProvider', () {
    test('starts with no highlights and no ghosts', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(templateApplyEffectsProvider(date));

      expect(state.highlightedIds, isEmpty);
      expect(state.ghosts, isEmpty);
    });

    test('addHighlights adds ids', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(templateApplyEffectsProvider(date).notifier).addHighlights(
        ['a', 'b'],
      );

      expect(
        container.read(templateApplyEffectsProvider(date)).highlightedIds,
        {'a', 'b'},
      );
    });

    test('removeHighlight removes one', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(templateApplyEffectsProvider(date).notifier)
        ..addHighlights(['a', 'b'])
        ..removeHighlight('a');
      expect(
        container.read(templateApplyEffectsProvider(date)).highlightedIds,
        {'b'},
      );
    });

    test('addGhosts assigns increasing ids and removeGhost removes one', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        templateApplyEffectsProvider(date).notifier,
      );

      final added = notifier.addGhosts([
        (start: DateTime(2026, 9, 14, 8), end: DateTime(2026, 9, 14, 9)),
        (start: DateTime(2026, 9, 14, 10), end: DateTime(2026, 9, 14, 11)),
      ]);

      expect(added.map((g) => g.id).toSet().length, 2);
      expect(container.read(templateApplyEffectsProvider(date)).ghosts, added);

      notifier.removeGhost(added.first.id);
      expect(container.read(templateApplyEffectsProvider(date)).ghosts, [
        added.last,
      ]);
    });

    test('effects for different dates are independent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final otherDate = DateTime(2026, 9, 15);

      container.read(templateApplyEffectsProvider(date).notifier).addHighlights(
        ['a'],
      );

      expect(
        container.read(templateApplyEffectsProvider(otherDate)).highlightedIds,
        isEmpty,
      );
    });
  });
}
