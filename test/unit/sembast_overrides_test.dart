import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/storage/sembast_overrides.dart';
import 'package:taskframe/features/category/data/sembast_category_repository.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/day/data/sembast_day_blocks_repository.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/saved_search/data/sembast_saved_search_repository.dart';
import 'package:taskframe/features/saved_search/providers.dart';
import 'package:taskframe/features/task/data/sembast_task_repository.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/template/data/sembast_template_repository.dart';
import 'package:taskframe/features/template/providers.dart';

void main() {
  test('sembastOverrides points every provider at sembast', () async {
    final db = await newDatabaseFactoryMemory().openDatabase('test.db');
    final container = ProviderContainer(overrides: sembastOverrides(db));
    addTearDown(container.dispose);

    expect(
      container.read(dayBlocksRepositoryProvider),
      isA<SembastDayBlocksRepository>(),
    );
    expect(
      container.read(categoryRepositoryProvider),
      isA<SembastCategoryRepository>(),
    );
    expect(
      container.read(templateRepositoryProvider),
      isA<SembastTemplateRepository>(),
    );
    expect(
      container.read(templateBlocksRepositoryProvider),
      isA<SembastTemplateBlocksRepository>(),
    );
    expect(
      container.read(appSettingsRepositoryProvider),
      isA<SembastAppSettingsRepository>(),
    );
    expect(
      container.read(taskRepositoryProvider),
      isA<SembastTaskRepository>(),
    );
    expect(
      container.read(savedSearchRepositoryProvider),
      isA<SembastSavedSearchRepository>(),
    );
  });
}
