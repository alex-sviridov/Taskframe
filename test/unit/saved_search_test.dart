// test/unit/saved_search_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/saved_search/models/saved_search.dart';

void main() {
  group('SavedSearch', () {
    final view = SavedSearch(
      id: 'view-1',
      name: 'Tasks view 1',
      query: '#urgent /work',
      order: 0,
    );

    test('round-trips through toMap/fromMap', () {
      expect(SavedSearch.fromMap(view.toMap()), view);
    });

    test('copyWith replaces only the given fields', () {
      final renamed = view.copyWith(name: 'Urgent work');

      expect(renamed.name, 'Urgent work');
      expect(renamed.query, view.query);
      expect(renamed.order, view.order);
    });

    test('toMap/fromMap round-trip updatedAt and deleted', () {
      final updatedAt = DateTime.utc(2026, 9, 15, 12);
      final view = SavedSearch(
        id: 's1',
        name: 'Work',
        query: '#work',
        order: 0,
        updatedAt: updatedAt,
        deleted: true,
      );
      final restored = SavedSearch.fromMap(view.toMap());
      expect(restored.updatedAt, updatedAt);
      expect(restored.deleted, isTrue);
    });
  });
}
