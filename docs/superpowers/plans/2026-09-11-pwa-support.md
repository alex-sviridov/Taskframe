# PWA Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist Taskframe's day blocks, categories, and templates locally via `sembast`, and make the web build a real iOS-installable PWA.

**Architecture:** Add `sembast`-backed implementations of the existing `DayBlocksRepository`/`CategoryRepository`/`TemplateRepository`/`TemplateBlocksRepository` interfaces, wired in only at the composition root (`main.dart`) via provider overrides — the existing `InMemory*` implementations stay as the default (test-safe) values of each repository provider, unchanged. A new `AppSettingsRepository` tracks install-hint dismissal the same way. The PWA shell (manifest/meta tags/build flags) and an iOS install-hint banner round out the installable experience.

**Tech Stack:** Flutter/Dart, `sembast` + `sembast_web` (cross-platform NoSQL store), `path_provider` (native file location), `uuid` (record ids), `web`/`dart:js_interop` (the two browser calls: standalone-display detection and `navigator.storage.persist()`), Riverpod (existing).

**Spec:** `docs/superpowers/specs/2026-09-11-pwa-support-design.md`

## Global Constraints

- Flutter web has no "html" DOM renderer (removed in Flutter 3.29) — do not touch rendering; stay on CanvasKit.
- No `freezed`/`json_serializable`/build_runner — serialization is hand-written `toMap()`/`fromMap()` on the existing plain model classes, matching current style.
- Persistence applies to every platform (web, iOS, Android) via one repository implementation per interface — no platform-conditional repository code (only the database *factory* is platform-conditional).
- Every existing repository provider's **default** value stays the current `InMemory*` implementation — only `main.dart` overrides it to the `Sembast*` implementation. This is required so the existing test suite (~20 files using bare `ProviderContainer()`/`ProviderScope()` with no overrides) keeps working unchanged.
- First-run seeding (today's five sample blocks, the default category) runs once, gated on the relevant store being empty, and only from `main.dart` — never from inside a repository.

---

### Task 1: Add storage dependencies

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: `sembast`, `sembast_web`, `path_provider`, `path`, `uuid`, `web` packages available to every later task.

- [ ] **Step 1: Add the dependencies**

Run:
```bash
flutter pub add sembast sembast_web path_provider path uuid web
```

- [ ] **Step 2: Verify it resolved cleanly**

Run: `flutter pub get`
Expected: exits 0, no version conflicts.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "Add sembast, path_provider, uuid, and web dependencies for PWA storage"
```

---

### Task 2: Model serialization (`toMap`/`fromMap`)

**Files:**
- Modify: `lib/features/day/models/time_object.dart`
- Modify: `lib/features/category/models/category.dart`
- Modify: `lib/features/template/models/template.dart`
- Test: `test/unit/time_object_test.dart`
- Test: `test/unit/category_test.dart`
- Test: `test/unit/template_test.dart`

**Interfaces:**
- Produces: `TimeObject.toMap()` / `TimeObject.fromMap(Map<String, Object?>)`, `Category.toMap()` / `Category.fromMap(Map<String, Object?>)`, `Template.toMap()` / `Template.fromMap(Map<String, Object?>)` — used by every `Sembast*Repository` in later tasks.

- [ ] **Step 1: Write the failing round-trip tests**

Append to `test/unit/time_object_test.dart`:

```dart
  group('toMap/fromMap', () {
    test('fromMap(toMap()) round-trips every field', () {
      final block = TimeObject(
        id: 'block-1',
        title: 'Standup',
        start: DateTime(2030, 1, 1, 9),
        end: DateTime(2030, 1, 1, 9, 30),
        kind: BlockKind.anchor,
        locked: false,
        categoryId: 'category-1',
      );

      final restored = TimeObject.fromMap(block.toMap());

      expect(restored.id, block.id);
      expect(restored.title, block.title);
      expect(restored.start, block.start);
      expect(restored.end, block.end);
      expect(restored.kind, block.kind);
      expect(restored.categoryId, block.categoryId);
    });

    test('toMap stores kind by name', () {
      final block = TimeObject(
        id: 'block-1',
        title: 'Work',
        start: DateTime(2030, 1, 1, 9),
        end: DateTime(2030, 1, 1, 10),
        kind: BlockKind.frame,
        locked: false,
      );

      expect(block.toMap()['kind'], 'frame');
    });
  });
```

Append to `test/unit/category_test.dart`:

```dart
  group('toMap/fromMap', () {
    test('fromMap(toMap()) round-trips every field', () {
      const category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      final restored = Category.fromMap(category.toMap());

      expect(restored.id, category.id);
      expect(restored.name, category.name);
      expect(restored.colorValue, category.colorValue);
      expect(restored.emoji, category.emoji);
    });

    test('fromMap restores a null emoji', () {
      const category = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
      );

      expect(Category.fromMap(category.toMap()).emoji, isNull);
    });
  });
```

Append to `test/unit/template_test.dart`:

```dart
  group('toMap/fromMap', () {
    test('fromMap(toMap()) round-trips every field', () {
      const template = Template(id: 'template-1', name: 'Weekday');

      final restored = Template.fromMap(template.toMap());

      expect(restored.id, template.id);
      expect(restored.name, template.name);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/time_object_test.dart test/unit/category_test.dart test/unit/template_test.dart`
Expected: FAIL — `toMap`/`fromMap` are not defined.

- [ ] **Step 3: Implement the serialization methods**

In `lib/features/day/models/time_object.dart`, add to the `TimeObject` class (after the existing `overlaps` method):

```dart
  /// This block's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'kind': kind.name,
    'locked': locked,
    'categoryId': categoryId,
  };

  /// Reconstructs a [TimeObject] from a map produced by [toMap].
  factory TimeObject.fromMap(Map<String, Object?> map) => TimeObject(
    id: map['id']! as String,
    title: map['title']! as String,
    start: DateTime.parse(map['start']! as String),
    end: DateTime.parse(map['end']! as String),
    kind: BlockKind.values.byName(map['kind']! as String),
    locked: map['locked']! as bool,
    categoryId: map['categoryId']! as String,
  );
```

In `lib/features/category/models/category.dart`, add to the `Category` class (after `copyWith`):

```dart
  /// This category's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'emoji': emoji,
  };

  /// Reconstructs a [Category] from a map produced by [toMap].
  factory Category.fromMap(Map<String, Object?> map) => Category(
    id: map['id']! as String,
    name: map['name']! as String,
    colorValue: map['colorValue']! as int,
    emoji: map['emoji'] as String?,
  );
```

In `lib/features/template/models/template.dart`, add to the `Template` class (after `copyWith`):

```dart
  /// This template's field values as a JSON-safe map, for storage.
  Map<String, Object?> toMap() => {'id': id, 'name': name};

  /// Reconstructs a [Template] from a map produced by [toMap].
  factory Template.fromMap(Map<String, Object?> map) =>
      Template(id: map['id']! as String, name: map['name']! as String);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/time_object_test.dart test/unit/category_test.dart test/unit/template_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/models/time_object.dart lib/features/category/models/category.dart lib/features/template/models/template.dart test/unit/time_object_test.dart test/unit/category_test.dart test/unit/template_test.dart
git commit -m "Add toMap/fromMap serialization to TimeObject, Category, and Template"
```

---

### Task 3: Sembast stores, date key, and database factory

**Files:**
- Create: `lib/core/storage/date_key.dart`
- Create: `lib/core/storage/app_database.dart`
- Create: `lib/core/storage/database_factory.dart`
- Create: `lib/core/storage/database_factory_stub.dart`
- Create: `lib/core/storage/database_factory_io.dart`
- Create: `lib/core/storage/database_factory_web.dart`
- Test: `test/unit/date_key_test.dart`
- Test: `test/unit/app_database_test.dart`

**Interfaces:**
- Produces: `String dateKeyFor(DateTime date)`; `StoreRef<String, Map<String, Object?>>` constants `dayBlocksStore`, `categoriesStore`, `templatesStore`, `templateBlocksStore`, `settingsStore`; `Future<Database> openAppDatabase()`.

- [ ] **Step 1: Write the failing `dateKeyFor` test**

Create `test/unit/date_key_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/date_key.dart';

void main() {
  group('dateKeyFor', () {
    test('formats as zero-padded yyyy-MM-dd', () {
      expect(dateKeyFor(DateTime(2030, 1, 5)), '2030-01-05');
    });

    test('two DateTimes on the same day produce the same key regardless '
        'of time of day', () {
      expect(
        dateKeyFor(DateTime(2030, 1, 5, 23, 59)),
        dateKeyFor(DateTime(2030, 1, 5, 0, 1)),
      );
    });

    test('different days produce different keys', () {
      expect(
        dateKeyFor(DateTime(2030, 1, 5)),
        isNot(dateKeyFor(DateTime(2030, 1, 6))),
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/date_key_test.dart`
Expected: FAIL — no file `lib/core/storage/date_key.dart`.

- [ ] **Step 3: Implement `date_key.dart`**

Create `lib/core/storage/date_key.dart`:

```dart
/// Formats [date] as a zero-padded `yyyy-MM-dd` string, ignoring its
/// time-of-day component. Used as the `dateKey` field on stored day
/// blocks, so `SembastDayBlocksRepository.load` can query "every block on
/// this calendar date" without relying on `DateTime` equality (which
/// would also compare hours/minutes).
String dateKeyFor(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/unit/date_key_test.dart`
Expected: PASS

- [ ] **Step 5: Write the failing store-names test**

Create `test/unit/app_database_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/app_database.dart';

void main() {
  test('every store has a distinct name', () {
    final names = {
      dayBlocksStore.name,
      categoriesStore.name,
      templatesStore.name,
      templateBlocksStore.name,
      settingsStore.name,
    };

    expect(names, hasLength(5));
  });
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/unit/app_database_test.dart`
Expected: FAIL — no file `lib/core/storage/app_database.dart`.

- [ ] **Step 7: Implement the database factory files and `app_database.dart`**

Create `lib/core/storage/database_factory_stub.dart`:

```dart
import 'package:sembast/sembast.dart';

/// Never selected at runtime — [database_factory.dart]'s conditional
/// export always resolves to either the io or web variant. Exists only
/// as the default branch conditional exports require.
DatabaseFactory createDatabaseFactory() =>
    throw UnsupportedError('No sembast factory available on this platform');

Future<String> databasePath() async =>
    throw UnsupportedError('No sembast factory available on this platform');
```

Create `lib/core/storage/database_factory_io.dart`:

```dart
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

DatabaseFactory createDatabaseFactory() => databaseFactoryIo;

Future<String> databasePath() async {
  final directory = await getApplicationDocumentsDirectory();
  return path.join(directory.path, 'taskframe.db');
}
```

Create `lib/core/storage/database_factory_web.dart`:

```dart
import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

DatabaseFactory createDatabaseFactory() => databaseFactoryWeb;

Future<String> databasePath() async => 'taskframe.db';
```

Create `lib/core/storage/database_factory.dart`:

```dart
/// Selects the platform-correct sembast [DatabaseFactory] and database
/// location: file-backed on native platforms, IndexedDB-backed on web.
export 'database_factory_stub.dart'
    if (dart.library.io) 'database_factory_io.dart'
    if (dart.library.html) 'database_factory_web.dart';
```

Create `lib/core/storage/app_database.dart`:

```dart
import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/database_factory.dart';

/// Day blocks, keyed by block id, each record carrying a `dateKey` field
/// (see `date_key.dart`) that `load` filters on.
final dayBlocksStore = stringMapStoreFactory.store('day_blocks');

/// Categories, keyed by category id, each record carrying an `order`
/// field that preserves creation order (with the default category
/// seeded at order 0, so it always sorts first).
final categoriesStore = stringMapStoreFactory.store('categories');

/// Templates, keyed by template id, each record carrying an `order`
/// field that preserves creation order.
final templatesStore = stringMapStoreFactory.store('templates');

/// Template blocks, keyed by block id, each record carrying a
/// `templateId` field that `load`/`deleteAll` filter on.
final templateBlocksStore = stringMapStoreFactory.store('template_blocks');

/// Small app settings (currently just install-hint dismissal), keyed by
/// setting name.
final settingsStore = stringMapStoreFactory.store('settings');

/// Opens the app's single sembast [Database], using the platform-correct
/// factory and location from `database_factory.dart`.
Future<Database> openAppDatabase() async {
  final factory = createDatabaseFactory();
  final path = await databasePath();
  return factory.openDatabase(path);
}
```

- [ ] **Step 8: Run to verify it passes**

Run: `flutter test test/unit/app_database_test.dart`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add lib/core/storage/ test/unit/date_key_test.dart test/unit/app_database_test.dart
git commit -m "Add sembast stores, date key helper, and platform database factory"
```

---

### Task 4: First-run seeding

**Files:**
- Create: `lib/core/storage/first_run_seed.dart`
- Test: `test/unit/first_run_seed_test.dart`

**Interfaces:**
- Consumes: `dayBlocksStore`, `categoriesStore` (from Task 3); `Category`/`TimeObject`/`BlockKind` and their `toMap()` (from Task 2); `dateKeyFor` (from Task 3).
- Produces: `Future<void> seedIfEmpty(Database db)` — called once from `main.dart` in Task 8.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/first_run_seed_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/date_key.dart';
import 'package:taskframe/core/storage/first_run_seed.dart';
import 'package:taskframe/features/category/models/category.dart';

void main() {
  group('seedIfEmpty', () {
    test('writes the default category when categories is empty', () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');

      await seedIfEmpty(db);

      final records = await categoriesStore.find(db);
      expect(records, hasLength(1));
      expect(records.single.key, Category.defaultId);
      expect(records.single.value['name'], 'Default');
    });

    test('writes five seed blocks for today when day_blocks is empty', () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');

      await seedIfEmpty(db);

      final records = await dayBlocksStore.find(db);
      expect(records, hasLength(5));
      final todayKey = dateKeyFor(DateTime.now());
      expect(records.every((r) => r.value['dateKey'] == todayKey), isTrue);
    });

    test('does not duplicate seed blocks on a second call', () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');

      await seedIfEmpty(db);
      await seedIfEmpty(db);

      expect(await dayBlocksStore.count(db), 5);
    });

    test('does not overwrite an existing category', () async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      const existing = Category(
        id: 'category-1',
        name: 'Work',
        colorValue: 0xFF2196F3,
      );
      await categoriesStore.record(existing.id).put(db, existing.toMap());

      await seedIfEmpty(db);

      final records = await categoriesStore.find(db);
      expect(records, hasLength(1));
      expect(records.single.key, 'category-1');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/first_run_seed_test.dart`
Expected: FAIL — no file `lib/core/storage/first_run_seed.dart`.

- [ ] **Step 3: Implement `first_run_seed.dart`**

Create `lib/core/storage/first_run_seed.dart`:

```dart
import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/date_key.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/models/time_object.dart';

/// Writes the app's original hardcoded sample data — today's five seed
/// blocks and the default category — into [db], but only the first time
/// it runs: each store is left untouched once it holds any record, so
/// this never overwrites real data on later launches.
Future<void> seedIfEmpty(Database db) async {
  if (await categoriesStore.count(db) == 0) {
    const defaultCategory = Category(
      id: Category.defaultId,
      name: 'Default',
      colorValue: 0xFF009688,
    );
    await categoriesStore
        .record(defaultCategory.id)
        .put(db, {...defaultCategory.toMap(), 'order': 0});
  }

  if (await dayBlocksStore.count(db) == 0) {
    final today = DateTime.now();
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(today.year, today.month, today.day, hour, minute);

    final seedBlocks = [
      TimeObject(
        id: 'breakfast',
        title: 'Breakfast',
        start: at(7),
        end: at(7, 30),
        kind: BlockKind.anchor,
        locked: false,
      ),
      TimeObject(
        id: 'commute',
        title: 'Commute',
        start: at(8),
        end: at(8, 30),
        kind: BlockKind.anchor,
        locked: false,
      ),
      TimeObject(
        id: 'work',
        title: 'Work',
        start: at(9),
        end: at(13),
        kind: BlockKind.frame,
        locked: false,
      ),
      TimeObject(
        id: 'lunch',
        title: 'Lunch',
        start: at(13),
        end: at(13, 30),
        kind: BlockKind.anchor,
        locked: false,
      ),
      TimeObject(
        id: 'cleaning',
        title: 'Cleaning',
        start: at(19),
        end: at(20),
        kind: BlockKind.frame,
        locked: false,
      ),
    ];

    final todayKey = dateKeyFor(today);
    for (final block in seedBlocks) {
      await dayBlocksStore
          .record(block.id)
          .put(db, {...block.toMap(), 'dateKey': todayKey});
    }
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/unit/first_run_seed_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/storage/first_run_seed.dart test/unit/first_run_seed_test.dart
git commit -m "Add first-run seeding for the default category and today's sample blocks"
```

---

### Task 5: `SembastDayBlocksRepository`

**Files:**
- Create: `lib/features/day/data/sembast_day_blocks_repository.dart`
- Test: `test/unit/sembast_day_blocks_repository_test.dart`

**Interfaces:**
- Consumes: `dayBlocksStore` (Task 3), `dateKeyFor` (Task 3), `TimeObject.toMap`/`fromMap` (Task 2), `DayBlocksRepository` (existing, `lib/features/day/data/day_blocks_repository.dart`).
- Produces: `class SembastDayBlocksRepository implements DayBlocksRepository` with constructor `SembastDayBlocksRepository(Database db)` — used by `main.dart` in Task 8.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/sembast_day_blocks_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/features/day/data/sembast_day_blocks_repository.dart';
import 'package:taskframe/features/day/models/time_object.dart';

void main() {
  group('SembastDayBlocksRepository', () {
    late SembastDayBlocksRepository repository;

    setUp(() async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastDayBlocksRepository(db);
    });

    test('load returns an empty list when nothing has been added', () async {
      expect(await repository.load(DateTime(2030, 1, 1)), isEmpty);
    });

    test('add returns a block with the given start, end and kind', () async {
      final added = await repository.add(
        DateTime(2030, 1, 1),
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      expect(added.start, DateTime(2030, 1, 1, 10));
      expect(added.end, DateTime(2030, 1, 1, 10, 30));
      expect(added.kind, BlockKind.anchor);
      expect(added.title, 'title');
    });

    test('add defaults categoryId to the default category', () async {
      final added = await repository.add(
        DateTime(2030, 1, 1),
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      expect(added.categoryId, '0');
    });

    test('a block added for a date shows up in a later load for that date', () async {
      final date = DateTime(2030, 1, 1);
      await repository.add(
        date,
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.frame,
      );

      final blocks = await repository.load(date);

      expect(blocks, hasLength(1));
      expect(blocks.single.kind, BlockKind.frame);
    });

    test('a block added for one date is invisible on another', () async {
      await repository.add(
        DateTime(2030, 1, 1),
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      expect(await repository.load(DateTime(2030, 1, 2)), isEmpty);
    });

    test('two added blocks get distinct ids', () async {
      final date = DateTime(2030, 1, 1);
      final first = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );
      final second = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 11),
        end: DateTime(2030, 1, 1, 11, 30),
        kind: BlockKind.anchor,
      );

      expect(first.id, isNot(second.id));
    });

    test('move updates start/end/date and is queryable on the new date', () async {
      final date = DateTime(2030, 1, 1);
      final laterDate = DateTime(2030, 1, 2);
      final added = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      final moved = await repository.move(
        added,
        fromDate: date,
        toDate: laterDate,
        newStart: DateTime(2030, 1, 2, 14),
        newEnd: DateTime(2030, 1, 2, 14, 30),
      );

      expect(moved.id, added.id);
      expect(await repository.load(date), isEmpty);
      final blocks = await repository.load(laterDate);
      expect(blocks, hasLength(1));
      expect(blocks.single.start, DateTime(2030, 1, 2, 14));
    });

    test('update changes title/start/end/kind, replacing the block in a '
        'later load', () async {
      final date = DateTime(2030, 1, 1);
      final added = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      final updated = await repository.update(
        added,
        date: date,
        title: 'Renamed',
        start: DateTime(2030, 1, 1, 11),
        end: DateTime(2030, 1, 1, 11, 30),
        kind: BlockKind.frame,
      );

      expect(updated.id, added.id);
      expect(updated.title, 'Renamed');
      expect(updated.kind, BlockKind.frame);
      final blocks = await repository.load(date);
      expect(blocks, hasLength(1));
      expect(blocks.single.title, 'Renamed');
    });

    test('update leaves categoryId unchanged when not given', () async {
      final date = DateTime(2030, 1, 1);
      final added = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
        categoryId: 'category-1',
      );

      final updated = await repository.update(
        added,
        date: date,
        title: 'Renamed',
      );

      expect(updated.categoryId, 'category-1');
    });

    test('delete removes the block from a later load', () async {
      final date = DateTime(2030, 1, 1);
      final added = await repository.add(
        date,
        start: DateTime(2030, 1, 1, 10),
        end: DateTime(2030, 1, 1, 10, 30),
        kind: BlockKind.anchor,
      );

      await repository.delete(added, date: date);

      expect(await repository.load(date), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/sembast_day_blocks_repository_test.dart`
Expected: FAIL — no file `lib/features/day/data/sembast_day_blocks_repository.dart`.

- [ ] **Step 3: Implement `SembastDayBlocksRepository`**

Create `lib/features/day/data/sembast_day_blocks_repository.dart`:

```dart
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/date_key.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/models/time_object.dart';

const _uuid = Uuid();

/// A [DayBlocksRepository] backed by a sembast [Database], persisting
/// blocks across restarts. Each record's key is the block's own [id];
/// `load` filters records by a stored `dateKey` field (see [dateKeyFor]).
class SembastDayBlocksRepository implements DayBlocksRepository {
  /// Creates a [SembastDayBlocksRepository] reading/writing [db].
  SembastDayBlocksRepository(this._db);

  final Database _db;

  @override
  Future<List<TimeObject>> load(DateTime date) async {
    final finder = Finder(filter: Filter.equals('dateKey', dateKeyFor(date)));
    final records = await dayBlocksStore.find(_db, finder: finder);
    return [for (final record in records) TimeObject.fromMap(record.value)];
  }

  @override
  Future<TimeObject> add(
    DateTime date, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  }) async {
    final block = TimeObject(
      id: _uuid.v4(),
      title: title ?? 'title',
      start: start,
      end: end,
      kind: kind,
      locked: false,
      categoryId: categoryId ?? Category.defaultId,
    );
    await dayBlocksStore
        .record(block.id)
        .put(_db, {...block.toMap(), 'dateKey': dateKeyFor(date)});
    return block;
  }

  @override
  Future<TimeObject> move(
    TimeObject block, {
    required DateTime fromDate,
    required DateTime toDate,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final moved = TimeObject(
      id: block.id,
      title: block.title,
      start: newStart,
      end: newEnd,
      kind: block.kind,
      locked: block.locked,
      categoryId: block.categoryId,
    );
    await dayBlocksStore
        .record(block.id)
        .put(_db, {...moved.toMap(), 'dateKey': dateKeyFor(toDate)});
    return moved;
  }

  @override
  Future<TimeObject> update(
    TimeObject block, {
    required DateTime date,
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  }) async {
    final updated = TimeObject(
      id: block.id,
      title: title ?? block.title,
      start: start ?? block.start,
      end: end ?? block.end,
      kind: kind ?? block.kind,
      locked: block.locked,
      categoryId: categoryId ?? block.categoryId,
    );
    await dayBlocksStore
        .record(block.id)
        .put(_db, {...updated.toMap(), 'dateKey': dateKeyFor(date)});
    return updated;
  }

  @override
  Future<void> delete(TimeObject block, {required DateTime date}) async {
    await dayBlocksStore.record(block.id).delete(_db);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/unit/sembast_day_blocks_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/day/data/sembast_day_blocks_repository.dart test/unit/sembast_day_blocks_repository_test.dart
git commit -m "Add SembastDayBlocksRepository"
```

---

### Task 6: `SembastCategoryRepository`

**Files:**
- Create: `lib/features/category/data/sembast_category_repository.dart`
- Test: `test/unit/sembast_category_repository_test.dart`

**Interfaces:**
- Consumes: `categoriesStore` (Task 3), `Category.toMap`/`fromMap` (Task 2), `CategoryRepository` (existing, `lib/features/category/data/category_repository.dart`).
- Produces: `class SembastCategoryRepository implements CategoryRepository` with constructor `SembastCategoryRepository(Database db)` — used by `main.dart` in Task 8.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/sembast_category_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/features/category/data/sembast_category_repository.dart';
import 'package:taskframe/features/category/models/category.dart';

void main() {
  group('SembastCategoryRepository', () {
    late SembastCategoryRepository repository;

    setUp(() async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastCategoryRepository(db);
    });

    test('load synthesizes the default category when the store has '
        'nothing yet', () async {
      final categories = await repository.load();

      expect(categories, hasLength(1));
      expect(categories.single.isDefault, isTrue);
    });

    test('add appends a new non-default category, after the default', () async {
      final added = await repository.add(
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      expect(added.isDefault, isFalse);
      final categories = await repository.load();
      expect(categories, hasLength(2));
      expect(categories.first.isDefault, isTrue);
      expect(categories.last.name, 'Work');
    });

    test('two added categories get distinct, non-default ids', () async {
      final first = await repository.add(name: 'Work', colorValue: 0xFF2196F3);
      final second = await repository.add(
        name: 'Health',
        colorValue: 0xFF4CAF50,
      );

      expect(first.id, isNot(second.id));
      expect(first.id, isNot(Category.defaultId));
    });

    test('added categories load back in creation order', () async {
      await repository.add(name: 'First', colorValue: 0xFF000001);
      await repository.add(name: 'Second', colorValue: 0xFF000002);

      final categories = await repository.load();

      expect(categories[1].name, 'First');
      expect(categories[2].name, 'Second');
    });

    test('update changes an added category\'s name, color and emoji', () async {
      final added = await repository.add(name: 'Work', colorValue: 0xFF2196F3);

      final updated = await repository.update(
        added,
        name: 'Career',
        colorValue: 0xFFFF0000,
        emoji: '🚀',
      );

      expect(updated.id, added.id);
      expect(updated.name, 'Career');
      expect(updated.colorValue, 0xFFFF0000);
      expect(updated.emoji, '🚀');
    });

    test('update leaves fields unspecified as null unchanged', () async {
      final added = await repository.add(
        name: 'Work',
        colorValue: 0xFF2196F3,
        emoji: '💼',
      );

      final updated = await repository.update(added, colorValue: 0xFFFF0000);

      expect(updated.name, 'Work');
      expect(updated.emoji, '💼');
    });

    test('update replaces the category in a later load', () async {
      final added = await repository.add(name: 'Work', colorValue: 0xFF2196F3);

      await repository.update(added, name: 'Career');

      final categories = await repository.load();
      expect(categories.singleWhere((c) => c.id == added.id).name, 'Career');
    });

    test('updating the default category only applies the color change', () async {
      final defaultCategory = (await repository.load()).single;

      final updated = await repository.update(
        defaultCategory,
        name: 'Renamed',
        colorValue: 0xFFFF0000,
        emoji: '🔥',
      );

      expect(updated.name, 'Default');
      expect(updated.emoji, isNull);
      expect(updated.colorValue, 0xFFFF0000);
    });

    test('delete removes an added category from a later load', () async {
      final added = await repository.add(name: 'Work', colorValue: 0xFF2196F3);

      await repository.delete(added);

      final categories = await repository.load();
      expect(categories.where((c) => c.id == added.id), isEmpty);
    });

    test('delete on the default category is a no-op', () async {
      final defaultCategory = (await repository.load()).single;

      await repository.delete(defaultCategory);

      final categories = await repository.load();
      expect(categories, hasLength(1));
      expect(categories.single.isDefault, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/sembast_category_repository_test.dart`
Expected: FAIL — no file `lib/features/category/data/sembast_category_repository.dart`.

- [ ] **Step 3: Implement `SembastCategoryRepository`**

Create `lib/features/category/data/sembast_category_repository.dart`:

```dart
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/category/data/category_repository.dart';
import 'package:taskframe/features/category/models/category.dart';

const _uuid = Uuid();

/// A [CategoryRepository] backed by a sembast [Database], persisting
/// categories across restarts. Records are keyed by [Category.id]; an
/// `order` field (set once at creation, preserved on update) keeps the
/// default category first and the rest in creation order.
///
/// The default category is expected to already exist — written by
/// first-run seeding — but [load] synthesizes one in memory if it's ever
/// missing, so callers always get it first regardless.
class SembastCategoryRepository implements CategoryRepository {
  /// Creates a [SembastCategoryRepository] reading/writing [db].
  SembastCategoryRepository(this._db);

  final Database _db;

  static const _fallbackDefault = Category(
    id: Category.defaultId,
    name: 'Default',
    colorValue: 0xFF009688,
  );

  @override
  Future<List<Category>> load() async {
    final finder = Finder(sortOrders: [SortOrder('order')]);
    final records = await categoriesStore.find(_db, finder: finder);
    final categories = [
      for (final record in records) Category.fromMap(record.value),
    ];
    if (categories.any((c) => c.isDefault)) return categories;
    return [_fallbackDefault, ...categories];
  }

  @override
  Future<Category> add({
    required String name,
    required int colorValue,
    String? emoji,
  }) async {
    final category = Category(
      id: _uuid.v4(),
      name: name,
      colorValue: colorValue,
      emoji: emoji,
    );
    await categoriesStore.record(category.id).put(_db, {
      ...category.toMap(),
      'order': DateTime.now().microsecondsSinceEpoch,
    });
    return category;
  }

  @override
  Future<Category> update(
    Category category, {
    String? name,
    int? colorValue,
    String? emoji,
  }) async {
    final existingRecord = await categoriesStore.record(category.id).get(_db);
    final current = existingRecord == null
        ? category
        : Category.fromMap(existingRecord);
    final updated = current.isDefault
        ? current.copyWith(colorValue: colorValue)
        : current.copyWith(name: name, colorValue: colorValue, emoji: emoji);
    final order =
        existingRecord?['order'] ?? DateTime.now().microsecondsSinceEpoch;
    await categoriesStore
        .record(updated.id)
        .put(_db, {...updated.toMap(), 'order': order});
    return updated;
  }

  @override
  Future<void> delete(Category category) async {
    if (category.isDefault) return;
    await categoriesStore.record(category.id).delete(_db);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/unit/sembast_category_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/category/data/sembast_category_repository.dart test/unit/sembast_category_repository_test.dart
git commit -m "Add SembastCategoryRepository"
```

---

### Task 7: `SembastTemplateRepository` and `SembastTemplateBlocksRepository`

**Files:**
- Create: `lib/features/template/data/sembast_template_repository.dart`
- Test: `test/unit/sembast_template_repository_test.dart`

**Interfaces:**
- Consumes: `templatesStore`/`templateBlocksStore` (Task 3), `Template.toMap`/`fromMap` (Task 2), `TimeObject.toMap`/`fromMap` (Task 2), `TemplateRepository`/`TemplateBlocksRepository` (existing, `lib/features/template/data/template_repository.dart`).
- Produces: `class SembastTemplateRepository implements TemplateRepository`, `class SembastTemplateBlocksRepository implements TemplateBlocksRepository`, both constructed with a `Database` — used by `main.dart` in Task 8.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/sembast_template_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/template/data/sembast_template_repository.dart';

void main() {
  group('SembastTemplateRepository', () {
    late SembastTemplateRepository repository;

    setUp(() async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastTemplateRepository(db);
    });

    test('load starts empty', () async {
      expect(await repository.load(), isEmpty);
    });

    test('add appends a template with the given name', () async {
      final added = await repository.add(name: 'Weekday');

      expect(added.name, 'Weekday');
      expect(await repository.load(), [added]);
    });

    test('add assigns distinct ids to successive templates', () async {
      final first = await repository.add(name: 'A');
      final second = await repository.add(name: 'B');

      expect(first.id, isNot(second.id));
    });

    test('templates load back in creation order', () async {
      await repository.add(name: 'First');
      await repository.add(name: 'Second');

      final templates = await repository.load();

      expect(templates[0].name, 'First');
      expect(templates[1].name, 'Second');
    });

    test('rename updates the template\'s name', () async {
      final added = await repository.add(name: 'Weekday');

      final renamed = await repository.rename(added, name: 'Renamed');

      expect(renamed.id, added.id);
      expect((await repository.load()).single.name, 'Renamed');
    });

    test('rename throws StateError if the template is not found', () async {
      const missing = Template(id: 't-missing', name: 'Weekday');

      expect(
        () => repository.rename(missing, name: 'Renamed'),
        throwsA(isA<StateError>()),
      );
    });

    test('delete removes the template', () async {
      final added = await repository.add(name: 'Weekday');

      await repository.delete(added);

      expect(await repository.load(), isEmpty);
    });
  });

  group('SembastTemplateBlocksRepository', () {
    late SembastTemplateBlocksRepository repository;

    setUp(() async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastTemplateBlocksRepository(db);
    });

    test('load starts empty for a fresh templateId', () async {
      expect(await repository.load('t1'), isEmpty);
    });

    test('add appends a block for the given templateId', () async {
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
        title: 'Standup',
      );

      expect(added.title, 'Standup');
      final blocks = await repository.load('t1');
      expect(blocks.single.id, added.id);
    });

    test('a block added to one templateId is invisible to another', () async {
      await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      expect(await repository.load('t2'), isEmpty);
    });

    test('move moves a block from one templateId to another', () async {
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      await repository.move(
        added,
        fromTemplateId: 't1',
        toTemplateId: 't2',
        newStart: DateTime(2000, 1, 1, 14),
        newEnd: DateTime(2000, 1, 1, 14, 30),
      );

      expect(await repository.load('t1'), isEmpty);
      final moved = (await repository.load('t2')).single;
      expect(moved.id, added.id);
      expect(moved.start, DateTime(2000, 1, 1, 14));
    });

    test('update persists a title change', () async {
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      await repository.update(added, templateId: 't1', title: 'Renamed');

      final updated = (await repository.load('t1')).single;
      expect(updated.title, 'Renamed');
    });

    test('delete removes the block', () async {
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      await repository.delete(added, templateId: 't1');

      expect(await repository.load('t1'), isEmpty);
    });

    test('deleteAll clears one templateId without touching another', () async {
      for (final templateId in ['t1', 't2']) {
        await repository.add(
          templateId,
          start: DateTime(2000, 1, 1, 9),
          end: DateTime(2000, 1, 1, 9, 30),
          kind: BlockKind.anchor,
        );
      }

      await repository.deleteAll('t1');

      expect(await repository.load('t1'), isEmpty);
      expect(await repository.load('t2'), hasLength(1));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/sembast_template_repository_test.dart`
Expected: FAIL — no file `lib/features/template/data/sembast_template_repository.dart`. (The `Template` reference in the test also needs its import — add `import 'package:taskframe/features/template/models/template.dart';` to the test file now, alongside the others.)

- [ ] **Step 3: Implement both repositories**

Create `lib/features/template/data/sembast_template_repository.dart`:

```dart
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/template/data/template_repository.dart';
import 'package:taskframe/features/template/models/template.dart';

const _uuid = Uuid();

/// A [TemplateRepository] backed by a sembast [Database], persisting
/// templates across restarts. Records are keyed by [Template.id]; an
/// `order` field (set once at creation, preserved on rename) keeps
/// `load` in creation order.
class SembastTemplateRepository implements TemplateRepository {
  /// Creates a [SembastTemplateRepository] reading/writing [db].
  SembastTemplateRepository(this._db);

  final Database _db;

  @override
  Future<List<Template>> load() async {
    final finder = Finder(sortOrders: [SortOrder('order')]);
    final records = await templatesStore.find(_db, finder: finder);
    return [for (final record in records) Template.fromMap(record.value)];
  }

  @override
  Future<Template> add({required String name}) async {
    final template = Template(id: _uuid.v4(), name: name);
    await templatesStore.record(template.id).put(_db, {
      ...template.toMap(),
      'order': DateTime.now().microsecondsSinceEpoch,
    });
    return template;
  }

  @override
  Future<Template> rename(Template template, {required String name}) async {
    final existingRecord = await templatesStore.record(template.id).get(_db);
    if (existingRecord == null) {
      throw StateError('Template ${template.id} not found');
    }
    final renamed = template.copyWith(name: name);
    await templatesStore.record(renamed.id).put(_db, {
      ...renamed.toMap(),
      'order': existingRecord['order'],
    });
    return renamed;
  }

  @override
  Future<void> delete(Template template) async {
    await templatesStore.record(template.id).delete(_db);
  }
}

/// A [TemplateBlocksRepository] backed by a sembast [Database],
/// persisting template blocks across restarts. Records are keyed by
/// block id, mirroring [SembastDayBlocksRepository] but with a
/// `templateId` field instead of a `dateKey`.
class SembastTemplateBlocksRepository implements TemplateBlocksRepository {
  /// Creates a [SembastTemplateBlocksRepository] reading/writing [db].
  SembastTemplateBlocksRepository(this._db);

  final Database _db;

  @override
  Future<List<TimeObject>> load(String templateId) async {
    final finder = Finder(filter: Filter.equals('templateId', templateId));
    final records = await templateBlocksStore.find(_db, finder: finder);
    return [for (final record in records) TimeObject.fromMap(record.value)];
  }

  @override
  Future<TimeObject> add(
    String templateId, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  }) async {
    final block = TimeObject(
      id: _uuid.v4(),
      title: title ?? 'title',
      start: start,
      end: end,
      kind: kind,
      locked: false,
      categoryId: categoryId ?? Category.defaultId,
    );
    await templateBlocksStore
        .record(block.id)
        .put(_db, {...block.toMap(), 'templateId': templateId});
    return block;
  }

  @override
  Future<TimeObject> move(
    TimeObject block, {
    required String fromTemplateId,
    required String toTemplateId,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final moved = TimeObject(
      id: block.id,
      title: block.title,
      start: newStart,
      end: newEnd,
      kind: block.kind,
      locked: block.locked,
      categoryId: block.categoryId,
    );
    await templateBlocksStore
        .record(block.id)
        .put(_db, {...moved.toMap(), 'templateId': toTemplateId});
    return moved;
  }

  @override
  Future<TimeObject> update(
    TimeObject block, {
    required String templateId,
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  }) async {
    final updated = TimeObject(
      id: block.id,
      title: title ?? block.title,
      start: start ?? block.start,
      end: end ?? block.end,
      kind: kind ?? block.kind,
      locked: block.locked,
      categoryId: categoryId ?? block.categoryId,
    );
    await templateBlocksStore
        .record(block.id)
        .put(_db, {...updated.toMap(), 'templateId': templateId});
    return updated;
  }

  @override
  Future<void> delete(TimeObject block, {required String templateId}) async {
    await templateBlocksStore.record(block.id).delete(_db);
  }

  @override
  Future<void> deleteAll(String templateId) async {
    final finder = Finder(filter: Filter.equals('templateId', templateId));
    await templateBlocksStore.delete(_db, finder: finder);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/unit/sembast_template_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/template/data/sembast_template_repository.dart test/unit/sembast_template_repository_test.dart
git commit -m "Add SembastTemplateRepository and SembastTemplateBlocksRepository"
```

---

### Task 8: Wire the sembast repositories into `main.dart`

**Files:**
- Modify: `lib/main.dart`
- Test: (none new — this task is verified by the existing suite, see Step 3)

**Interfaces:**
- Consumes: `openAppDatabase()`, `seedIfEmpty()` (Tasks 3–4), all four `Sembast*Repository` classes (Tasks 5–7), `dayBlocksRepositoryProvider`/`categoryRepositoryProvider`/`templateRepositoryProvider`/`templateBlocksRepositoryProvider` (existing, unchanged).

- [ ] **Step 1: Update `main.dart`**

Replace the contents of `lib/main.dart`:

```dart
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
```

- [ ] **Step 2: Run the full test suite to confirm no regression**

Run: `flutter test`
Expected: PASS — every existing test still passes, since none of them touch `main.dart` or override these providers themselves (they use `InMemory*` via each provider's default, exactly as before).

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "Wire sembast-backed repositories into the app via main.dart overrides"
```

---

### Task 9: iOS PWA shell (manifest, meta tags, build flag)

**Files:**
- Modify: `web/index.html`
- Modify: `Makefile`

**Interfaces:** none (no Dart code) — verified by inspection, not `flutter test`.

- [ ] **Step 1: Update `web/index.html`**

In the `<head>` of `web/index.html`, replace the existing iOS meta tags block:

```html
  <!-- iOS meta tags & icons -->
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="taskframe">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
```

with:

```html
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#0175C2">

  <!-- iOS meta tags & icons -->
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black">
  <meta name="apple-mobile-web-app-title" content="taskframe">
  <link rel="apple-touch-icon" sizes="180x180" href="icons/Icon-192.png">
```

(The 192×192 PNG is reused at a 180×180 *display* size via the `sizes` hint — iOS accepts any square source and scales it; producing a true 180×180 asset is a follow-up design task, not a code change, so it's not part of this plan.)

- [ ] **Step 2: Verify by inspection**

Run: `grep -A8 "iOS meta tags" web/index.html`
Expected: shows the new block, including the viewport and theme-color tags added just above it.

- [ ] **Step 3: Add the `--pwa-strategy` build flag**

In `Makefile`, change:

```makefile
build-web:
	flutter build web --release
```

to:

```makefile
build-web:
	flutter build web --release --pwa-strategy=offline-first
```

- [ ] **Step 4: Verify by inspection**

Run: `grep "build-web:" -A1 Makefile`
Expected: shows the updated `flutter build web` line with `--pwa-strategy=offline-first`.

- [ ] **Step 5: Commit**

```bash
git add web/index.html Makefile
git commit -m "Add iOS PWA meta tags, viewport, theme-color, and offline-first build flag"
```

---

### Task 10: Best-effort persistent storage request

**Files:**
- Create: `lib/core/platform/persistent_storage.dart`
- Create: `lib/core/platform/persistent_storage_stub.dart`
- Create: `lib/core/platform/persistent_storage_web.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Produces: `Future<void> requestPersistentStorage()` — called once from `main.dart`.

- [ ] **Step 1: Create the conditional-import files**

Create `lib/core/platform/persistent_storage_stub.dart`:

```dart
/// No-op on every platform except web (see `persistent_storage_web.dart`).
Future<void> requestPersistentStorage() async {}
```

Create `lib/core/platform/persistent_storage_web.dart`:

```dart
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Asks the browser to mark this origin's storage as "persistent" — a
/// best-effort hint that reduces (but does not guarantee) the odds of
/// iOS Safari evicting IndexedDB data under storage pressure. Never
/// throws: an unsupported or denied request is not an error worth
/// surfacing, since the app already works without it.
Future<void> requestPersistentStorage() async {
  try {
    await web.window.navigator.storage.persist().toDart;
  } catch (_) {
    // Best-effort only.
  }
}
```

Create `lib/core/platform/persistent_storage.dart`:

```dart
/// Requests persistent storage from the browser, on platforms that
/// support it. A no-op everywhere else.
export 'persistent_storage_stub.dart'
    if (dart.library.html) 'persistent_storage_web.dart';
```

- [ ] **Step 2: Call it from `main.dart`**

In `lib/main.dart`, add the import:

```dart
import 'package:taskframe/core/platform/persistent_storage.dart';
```

and add the call right after `await seedIfEmpty(db);`:

```dart
  await seedIfEmpty(db);
  await requestPersistentStorage();
```

- [ ] **Step 3: Run the full test suite to confirm no regression**

Run: `flutter test`
Expected: PASS — `main.dart` isn't exercised by `flutter test` (tests build widgets directly), so this is a smoke check that nothing else broke.

- [ ] **Step 4: Commit**

```bash
git add lib/core/platform/persistent_storage.dart lib/core/platform/persistent_storage_stub.dart lib/core/platform/persistent_storage_web.dart lib/main.dart
git commit -m "Request persistent storage as a best-effort hint on web startup"
```

---

### Task 11: Install-hint dismissal storage (`AppSettingsRepository`)

**Files:**
- Create: `lib/core/storage/app_settings_repository.dart`
- Modify: `lib/main.dart`
- Test: `test/unit/app_settings_repository_test.dart`

**Interfaces:**
- Consumes: `settingsStore` (Task 3).
- Produces: `abstract class AppSettingsRepository { Future<DateTime?> getInstallHintDismissedAt(); Future<void> setInstallHintDismissedAt(DateTime time); }`, `class InMemoryAppSettingsRepository implements AppSettingsRepository`, `class SembastAppSettingsRepository implements AppSettingsRepository`, `final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(...)` — consumed by Task 12's visibility provider.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/app_settings_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';

void main() {
  group('InMemoryAppSettingsRepository', () {
    test('getInstallHintDismissedAt starts null', () async {
      final repository = InMemoryAppSettingsRepository();
      expect(await repository.getInstallHintDismissedAt(), isNull);
    });

    test('setInstallHintDismissedAt is read back by get', () async {
      final repository = InMemoryAppSettingsRepository();
      final time = DateTime(2030, 1, 1);

      await repository.setInstallHintDismissedAt(time);

      expect(await repository.getInstallHintDismissedAt(), time);
    });
  });

  group('SembastAppSettingsRepository', () {
    late SembastAppSettingsRepository repository;

    setUp(() async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastAppSettingsRepository(db);
    });

    test('getInstallHintDismissedAt starts null', () async {
      expect(await repository.getInstallHintDismissedAt(), isNull);
    });

    test('setInstallHintDismissedAt is read back by get', () async {
      final time = DateTime(2030, 1, 1, 12, 30);

      await repository.setInstallHintDismissedAt(time);

      expect(await repository.getInstallHintDismissedAt(), time);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/app_settings_repository_test.dart`
Expected: FAIL — no file `lib/core/storage/app_settings_repository.dart`.

- [ ] **Step 3: Implement `app_settings_repository.dart`**

Create `lib/core/storage/app_settings_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';

/// Loads and stores small, single-value app settings — currently just
/// when the iOS install hint was last dismissed.
abstract class AppSettingsRepository {
  /// When the install hint was last dismissed, or `null` if never.
  Future<DateTime?> getInstallHintDismissedAt();

  /// Records that the install hint was dismissed at [time].
  Future<void> setInstallHintDismissedAt(DateTime time);
}

/// An [AppSettingsRepository] that keeps its value in memory for the
/// life of the app.
class InMemoryAppSettingsRepository implements AppSettingsRepository {
  DateTime? _dismissedAt;

  @override
  Future<DateTime?> getInstallHintDismissedAt() async => _dismissedAt;

  @override
  Future<void> setInstallHintDismissedAt(DateTime time) async {
    _dismissedAt = time;
  }
}

/// An [AppSettingsRepository] backed by a sembast [Database], persisting
/// the dismissal time across restarts.
class SembastAppSettingsRepository implements AppSettingsRepository {
  /// Creates a [SembastAppSettingsRepository] reading/writing [db].
  SembastAppSettingsRepository(this._db);

  final Database _db;

  static const _key = 'install_hint_dismissed_at';

  @override
  Future<DateTime?> getInstallHintDismissedAt() async {
    final record = await settingsStore.record(_key).get(_db);
    final iso = record?['value'] as String?;
    return iso == null ? null : DateTime.parse(iso);
  }

  @override
  Future<void> setInstallHintDismissedAt(DateTime time) async {
    await settingsStore
        .record(_key)
        .put(_db, {'value': time.toIso8601String()});
  }
}

/// The backing store for app settings. Overriding this single provider
/// (as `main.dart` does with [SembastAppSettingsRepository]) is enough to
/// persist settings; nothing downstream needs to change.
final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => InMemoryAppSettingsRepository(),
);
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/unit/app_settings_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Override it in `main.dart`**

In `lib/main.dart`, add the import:

```dart
import 'package:taskframe/core/storage/app_settings_repository.dart';
```

and add one more entry to the `overrides` list (after `templateBlocksRepositoryProvider`'s):

```dart
        appSettingsRepositoryProvider.overrideWithValue(
          SembastAppSettingsRepository(db),
        ),
```

- [ ] **Step 6: Run the full test suite to confirm no regression**

Run: `flutter test`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/core/storage/app_settings_repository.dart lib/main.dart test/unit/app_settings_repository_test.dart
git commit -m "Add AppSettingsRepository for install-hint dismissal state"
```

---

### Task 12: iOS install-hint banner

**Files:**
- Create: `lib/core/platform/standalone_display.dart`
- Create: `lib/core/platform/standalone_display_stub.dart`
- Create: `lib/core/platform/standalone_display_web.dart`
- Create: `lib/core/widgets/ios_install_hint_banner.dart`
- Modify: `lib/core/widgets/app_shell.dart`
- Test: `test/widget/ios_install_hint_banner_test.dart`

**Interfaces:**
- Consumes: `appSettingsRepositoryProvider` (Task 11).
- Produces: `final isIosBrowserTabProvider = Provider<bool>(...)`, `final installHintVisibleProvider = FutureProvider<bool>(...)`, `class IosInstallHintBanner extends ConsumerWidget` — both providers overridable in tests and wired into `AppShell`.

- [ ] **Step 1: Create the standalone-display conditional-import files**

Create `lib/core/platform/standalone_display_stub.dart`:

```dart
/// Always `false` off web — there is no browser "standalone display
/// mode" concept to detect.
bool isStandaloneDisplayMode() => false;
```

Create `lib/core/platform/standalone_display_web.dart`:

```dart
import 'package:web/web.dart' as web;

/// Whether the page is currently running in the browser's "standalone"
/// display mode — true once a PWA has been added to the home screen and
/// launched from there, false for a normal browser tab.
bool isStandaloneDisplayMode() =>
    web.window.matchMedia('(display-mode: standalone)').matches;
```

Create `lib/core/platform/standalone_display.dart`:

```dart
export 'standalone_display_stub.dart'
    if (dart.library.html) 'standalone_display_web.dart';
```

- [ ] **Step 2: Write the failing widget tests**

Create `test/widget/ios_install_hint_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/widgets/ios_install_hint_banner.dart';

class _FakeAppSettingsRepository implements AppSettingsRepository {
  _FakeAppSettingsRepository({DateTime? dismissedAt}) : _dismissedAt = dismissedAt;
  DateTime? _dismissedAt;

  @override
  Future<DateTime?> getInstallHintDismissedAt() async => _dismissedAt;

  @override
  Future<void> setInstallHintDismissedAt(DateTime time) async {
    _dismissedAt = time;
  }
}

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        home: Scaffold(body: IosInstallHintBanner()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('IosInstallHintBanner', () {
    testWidgets('is hidden when not an iOS browser tab', (tester) async {
      await _pump(tester, [
        isIosBrowserTabProvider.overrideWithValue(false),
        appSettingsRepositoryProvider.overrideWithValue(
          _FakeAppSettingsRepository(),
        ),
      ]);

      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('is shown on an iOS browser tab with no prior dismissal', (
      tester,
    ) async {
      await _pump(tester, [
        isIosBrowserTabProvider.overrideWithValue(true),
        appSettingsRepositoryProvider.overrideWithValue(
          _FakeAppSettingsRepository(),
        ),
      ]);

      expect(find.byType(MaterialBanner), findsOneWidget);
    });

    testWidgets('is hidden shortly after being dismissed', (tester) async {
      await _pump(tester, [
        isIosBrowserTabProvider.overrideWithValue(true),
        appSettingsRepositoryProvider.overrideWithValue(
          _FakeAppSettingsRepository(dismissedAt: DateTime.now()),
        ),
      ]);

      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('is shown again after the cooldown has passed', (
      tester,
    ) async {
      await _pump(tester, [
        isIosBrowserTabProvider.overrideWithValue(true),
        appSettingsRepositoryProvider.overrideWithValue(
          _FakeAppSettingsRepository(
            dismissedAt: DateTime.now().subtract(const Duration(days: 15)),
          ),
        ),
      ]);

      expect(find.byType(MaterialBanner), findsOneWidget);
    });

    testWidgets('dismiss button hides the banner and records the '
        'dismissal', (tester) async {
      final repository = _FakeAppSettingsRepository();
      await _pump(tester, [
        isIosBrowserTabProvider.overrideWithValue(true),
        appSettingsRepositoryProvider.overrideWithValue(repository),
      ]);
      expect(find.byType(MaterialBanner), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pump();

      expect(find.byType(MaterialBanner), findsNothing);
      expect(await repository.getInstallHintDismissedAt(), isNotNull);
    });
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/widget/ios_install_hint_banner_test.dart`
Expected: FAIL — no file `lib/core/widgets/ios_install_hint_banner.dart`.

- [ ] **Step 4: Implement the banner and its providers**

Create `lib/core/widgets/ios_install_hint_banner.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/platform/standalone_display.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';

/// How long after a dismissal the install hint stays hidden before it's
/// eligible to show again.
const _dismissCooldown = Duration(days: 14);

/// Whether the app is currently running as an iOS Safari browser tab —
/// i.e. iOS, on the web, and not already launched from the home screen.
/// A [Provider] (rather than a plain function) so tests can override it
/// without needing a real browser.
final isIosBrowserTabProvider = Provider<bool>(
  (ref) =>
      kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      !isStandaloneDisplayMode(),
);

/// Whether [IosInstallHintBanner] should currently be shown: only on an
/// iOS browser tab, and only if it's never been dismissed or the
/// dismissal is older than [_dismissCooldown].
final installHintVisibleProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(isIosBrowserTabProvider)) return false;

  final dismissedAt = await ref
      .watch(appSettingsRepositoryProvider)
      .getInstallHintDismissedAt();
  if (dismissedAt == null) return true;

  return DateTime.now().difference(dismissedAt) > _dismissCooldown;
});

/// A dismissible banner teaching iOS Safari users how to install
/// Taskframe, shown when [installHintVisibleProvider] resolves `true`.
/// iOS has no native install prompt (no `beforeinstallprompt`), so this
/// is the only way users learn about Share → Add to Home Screen.
class IosInstallHintBanner extends ConsumerWidget {
  /// Creates an [IosInstallHintBanner].
  const IosInstallHintBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(installHintVisibleProvider).value ?? false;
    if (!visible) return const SizedBox.shrink();

    return MaterialBanner(
      content: const Text(
        'Install Taskframe: tap Share, then "Add to Home Screen".',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref
                .read(appSettingsRepositoryProvider)
                .setInstallHintDismissedAt(DateTime.now());
            ref.invalidate(installHintVisibleProvider);
          },
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/widget/ios_install_hint_banner_test.dart`
Expected: PASS

- [ ] **Step 6: Wire the banner into `AppShell`**

In `lib/core/widgets/app_shell.dart`, add the import:

```dart
import 'package:taskframe/core/widgets/ios_install_hint_banner.dart';
```

Change the narrow-width branch's `body:` from:

```dart
        body: Builder(
          builder: (context) => Stack(
            children: [
              navigationShell,
              Positioned(
                top: MediaQuery.paddingOf(context).top,
                left: 4,
                child: IconButton(
                  tooltip: 'Menu',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ],
          ),
        ),
```

to:

```dart
        body: Column(
          children: [
            const IosInstallHintBanner(),
            Expanded(
              child: Builder(
                builder: (context) => Stack(
                  children: [
                    navigationShell,
                    Positioned(
                      top: MediaQuery.paddingOf(context).top,
                      left: 4,
                      child: IconButton(
                        tooltip: 'Menu',
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
```

Change the wide-width branch's `body:` from:

```dart
    return Scaffold(
      body: Row(
        children: [
```

to:

```dart
    return Scaffold(
      body: Column(
        children: [
          const IosInstallHintBanner(),
          Expanded(child: _wideBody(navigationShell)),
        ],
      ),
    );
  }

  Widget _wideBody(StatefulNavigationShell navigationShell) {
    return Row(
      children: [
```

and change that branch's closing to match — the full wide-width `build` method becomes:

```dart
    return Scaffold(
      body: Column(
        children: [
          const IosInstallHintBanner(),
          Expanded(child: _wideBody(navigationShell)),
        ],
      ),
    );
  }

  Widget _wideBody(StatefulNavigationShell navigationShell) {
    return Row(
      children: [
        // NavigationDrawer has no width parameter of its own — it always
        // builds a Drawer, whose default width (304) is baked in via a
        // tight BoxConstraints.expand, so shrinking it as a persistent
        // sidebar means constraining it from outside like this rather
        // than passing it any property directly.
        SizedBox(
          width: _sidebarWidth,
          child: NavigationDrawer(
            // The narrower sidebar no longer has room for the default
            // tile padding (24px total) without its longest label
            // ("Categories") overflowing.
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: navigationShell.goBranch,
            children: _drawerDestinations(),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: navigationShell),
      ],
    );
  }
```

- [ ] **Step 7: Run the full test suite to confirm no regression**

Run: `flutter test`
Expected: PASS — `AppShell`'s existing tests (via `router_test.dart` and similar) don't assert on the exact `body` widget tree depth, only on navigation behavior and visible destinations, so wrapping `body` in a `Column` shouldn't break them. If any test does assert a specific ancestor chain from `Scaffold` to `navigationShell`, update that assertion to account for the new `Column`/`Expanded` wrapper.

- [ ] **Step 8: Commit**

```bash
git add lib/core/platform/standalone_display.dart lib/core/platform/standalone_display_stub.dart lib/core/platform/standalone_display_web.dart lib/core/widgets/ios_install_hint_banner.dart lib/core/widgets/app_shell.dart test/widget/ios_install_hint_banner_test.dart
git commit -m "Add iOS install-hint banner, wired into AppShell"
```

---

## Final verification

- [ ] Run `make check` (format-check + analyze + test + e2e) and confirm everything passes.
- [ ] Manually verify (per the spec's "not unit-testable" list): build with `make build-web`, serve it, and confirm on an iOS device/simulator that the app installs via Share → Add to Home Screen, launches standalone, and that data survives a full app restart.
