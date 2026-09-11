import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/app.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/first_run_seed.dart';
import 'package:taskframe/features/category/data/sembast_category_repository.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/day/data/sembast_day_blocks_repository.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/template/data/sembast_template_repository.dart';
import 'package:taskframe/features/template/providers.dart';

/// Entry point: opens the local database, seeds it on first run, then
/// boots the app inside a [ProviderScope] that overrides every repository
/// provider with its sembast-backed implementation.
///
/// The providers' own defaults stay the original `InMemory*`
/// implementations — only this composition root ever points them at real
/// storage, which is what keeps every existing test (built around a bare
/// `ProviderContainer()`/`ProviderScope()` with no overrides) working
/// unchanged.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();
  await seedIfEmpty(db);

  runApp(
    ProviderScope(
      overrides: [
        dayBlocksRepositoryProvider.overrideWithValue(
          SembastDayBlocksRepository(db),
        ),
        categoryRepositoryProvider.overrideWithValue(
          SembastCategoryRepository(db),
        ),
        templateRepositoryProvider.overrideWithValue(
          SembastTemplateRepository(db),
        ),
        templateBlocksRepositoryProvider.overrideWithValue(
          SembastTemplateBlocksRepository(db),
        ),
      ],
      child: const App(),
    ),
  );
}
