import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/app_database.dart';

void main() {
  test('every store has a distinct name', () {
    final names = {
      dayBlocksStore.name,
      categoriesStore.name,
      tasksStore.name,
      templatesStore.name,
      templateBlocksStore.name,
      settingsStore.name,
      savedSearchesStore.name,
    };

    expect(names, hasLength(7));
  });
}
