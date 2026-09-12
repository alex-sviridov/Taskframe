import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/features/category/data/sembast_category_repository.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/day/data/sembast_day_blocks_repository.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/task/data/sembast_task_repository.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/template/data/sembast_template_repository.dart';
import 'package:taskframe/features/template/providers.dart';

/// The provider overrides that point every repository at sembast-backed
/// storage in [db], used at the app's composition root (`main.dart`).
/// Kept as a standalone, testable list so a new repository provider added
/// without an entry here doesn't silently ship without persistence.
List<Override> sembastOverrides(Database db) => [
  dayBlocksRepositoryProvider.overrideWithValue(SembastDayBlocksRepository(db)),
  categoryRepositoryProvider.overrideWithValue(SembastCategoryRepository(db)),
  templateRepositoryProvider.overrideWithValue(SembastTemplateRepository(db)),
  templateBlocksRepositoryProvider.overrideWithValue(
    SembastTemplateBlocksRepository(db),
  ),
  appSettingsRepositoryProvider.overrideWithValue(
    SembastAppSettingsRepository(db),
  ),
  taskRepositoryProvider.overrideWithValue(SembastTaskRepository(db)),
];
