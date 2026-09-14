// test/unit/saved_search_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/saved_search/models/saved_search.dart';

void main() {
  group('SavedSearch', () {
    const view = SavedSearch(
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
  });
}
