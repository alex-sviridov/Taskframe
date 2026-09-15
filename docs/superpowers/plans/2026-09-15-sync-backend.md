# Sync Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give taskframe multi-device sync via a self-hosted PocketBase instance, paired by a no-login code, with last-write-wins conflict resolution — without changing how the app behaves offline.

**Architecture:** A generic, raw-`Map`-based `SyncEngine` iterates a fixed list of `SyncCollection`s (one per sembast store: tasks, categories, templates, template_blocks, saved_searches, day_blocks). For each, it pushes locally-changed records and pulls remotely-changed records through a thin `PocketBaseSyncClient` wrapper around the official `pocketbase` Dart SDK, resolving conflicts purely by comparing each record's `updatedAt`/`updated_at` timestamp. Every synced model gains `updatedAt`/`deleted` fields; deletes become soft-deletes (tombstones) so they propagate. The server side is unmodified PocketBase — six flexible-schema collections plus a `sync_groups` auth collection where the pairing code doubles as the record's password.

**Tech Stack:** Flutter/Dart (existing), `sembast` (existing, unchanged as local store), `pocketbase` Dart SDK (new), `connectivity_plus` (new, for the reconnect trigger), self-hosted PocketBase server in Docker (new).

**Spec:** `docs/superpowers/specs/2026-09-15-sync-backend-design.md`

## Global Constraints

- No real user accounts — identity is a pairing code shared by a `sync_groups` PocketBase auth record (spec: "No accounts — pairing code as the auth mechanism").
- Conflict resolution is last-write-wins by timestamp only — no field-level merge, no manual resolution UI (spec: "Conflict resolution is last-write-wins").
- Sembast stays the local source of truth; the app must work fully offline regardless of sync state (spec: "Any change to sembast as the local source of truth or to how the app behaves offline" is out of scope).
- Sync triggers are app start, connectivity regained, and a ~30s foreground timer — no realtime/websocket subscriptions in v1 (spec: "Sync triggers").
- Six collections: `tasks`, `categories`, `templates`, `template_blocks`, `saved_searches`, `day_blocks` (spec, as amended to include `template_blocks`).
- Every synced collection record carries `sync_group`, `updated_at`, `deleted`, `data` (spec: "One collection per entity type, each with a flexible `data` JSON field").

---

## File Structure

New files:
- `docker-compose.yml` — root-level, adds a `pocketbase` service alongside the existing app image
- `pocketbase/Dockerfile` — pins and packages the PocketBase binary
- `scripts/setup_pocketbase.dart` — one-time collection setup via PocketBase's admin import API
- `lib/core/sync/sync_collection.dart` — `SyncCollection` config type + the fixed list of six
- `lib/core/sync/sync_engine.dart` — generic push/pull/LWW engine, operates on raw sembast maps
- `lib/core/sync/pocketbase_sync_client.dart` — pairing + per-collection push/pull over the `pocketbase` SDK
- `lib/core/sync/sync_trigger.dart` — wires app-start/connectivity/timer triggers to `SyncEngine.syncAll`
- `lib/features/pairing/widgets/pairing_screen.dart` — create/join-group UI
- `lib/features/pairing/pairing_providers.dart` — pairing state + actions
- Tests: `test/unit/sync_engine_test.dart`, `test/unit/app_settings_repository_test.dart` (extended), `test/unit/time_object_test.dart` (extended), one extended unit test per touched model/repo, `test/widget/pairing_screen_test.dart`, `e2e`/integration test for push/pull against a real local PocketBase (see Task 11)

Modified files:
- `lib/features/task/models/task.dart`, `.../data/sembast_task_repository.dart`
- `lib/features/category/models/category.dart`, `.../data/sembast_category_repository.dart`
- `lib/features/template/models/template.dart`, `.../data/sembast_template_repository.dart` (covers both `SembastTemplateRepository` and `SembastTemplateBlocksRepository`)
- `lib/features/day/models/time_object.dart`, `.../data/sembast_day_blocks_repository.dart`
- `lib/features/saved_search/models/saved_search.dart`, `.../data/sembast_saved_search_repository.dart`
- `lib/core/storage/app_settings_repository.dart` (generic cursor/pairing key-value storage)
- `lib/main.dart` (start sync triggers)
- `lib/router.dart` (pairing screen route)
- `pubspec.yaml` (`pocketbase`, `connectivity_plus`)

---

### Task 1: PocketBase server (Docker service + collection setup)

**Files:**
- Create: `pocketbase/Dockerfile`
- Create: `docker-compose.yml`
- Create: `scripts/setup_pocketbase.dart`

**Interfaces:**
- Produces: a running PocketBase instance on `http://localhost:8090` with six base collections (`tasks`, `categories`, `templates`, `template_blocks`, `saved_searches`, `day_blocks`) and one auth collection (`sync_groups`), each base collection scoped by API rule `sync_group = @request.auth.id`. Later tasks' `PocketBaseSyncClient` (Task 9) talks to this.

- [ ] **Step 1: Write the PocketBase Dockerfile**

```dockerfile
# pocketbase/Dockerfile
FROM alpine:3.20
ARG PB_VERSION=0.28.4
RUN apk add --no-cache ca-certificates unzip curl \
    && curl -Lo /tmp/pb.zip https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip \
    && unzip /tmp/pb.zip -d /pb \
    && rm /tmp/pb.zip
WORKDIR /pb
EXPOSE 8090
ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090"]
```

- [ ] **Step 2: Add the `pocketbase` service to `docker-compose.yml`**

```yaml
# docker-compose.yml
services:
  pocketbase:
    build: ./pocketbase
    ports:
      - "8090:8090"
    volumes:
      - pocketbase_data:/pb/pb_data

volumes:
  pocketbase_data:
```

- [ ] **Step 3: Bring the service up and create a superuser**

Run: `docker compose up -d pocketbase`
Run: `docker compose exec pocketbase /pb/pocketbase superuser upsert dev@taskframe.local dev-password-change-me`
Expected: both commands succeed; `curl -s http://localhost:8090/api/health` returns `{"code":200,...}`.

- [ ] **Step 4: Write the collection setup script**

```dart
// scripts/setup_pocketbase.dart
//
// One-time setup: creates the sync_groups auth collection and the six
// base sync collections via PocketBase's admin import API. Safe to
// re-run — import replaces collections by name, it doesn't duplicate
// them. Run with:
//   dart run scripts/setup_pocketbase.dart <baseUrl> <superuserEmail> <superuserPassword>
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run scripts/setup_pocketbase.dart <baseUrl> <email> <password>',
    );
    exitCode = 64;
    return;
  }
  final baseUrl = args[0];
  final email = args[1];
  final password = args[2];
  final client = HttpClient();

  Future<String> authenticate() async {
    final request = await client.postUrl(
      Uri.parse('$baseUrl/api/collections/_superusers/auth-with-password'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'identity': email, 'password': password}));
    final response = await request.close();
    final body = jsonDecode(await response.transform(utf8.decoder).join());
    if (response.statusCode != 200) {
      throw StateError('Auth failed (${response.statusCode}): $body');
    }
    return body['token'] as String;
  }

  Map<String, Object?> baseCollection(String name) => {
    'name': name,
    'type': 'base',
    'fields': [
      {'name': 'entity_id', 'type': 'text', 'required': true},
      {'name': 'sync_group', 'type': 'text', 'required': true},
      {'name': 'updated_at', 'type': 'text', 'required': true},
      {'name': 'deleted', 'type': 'bool', 'required': false},
      {'name': 'data', 'type': 'json', 'required': true},
    ],
    'indexes': [
      'CREATE INDEX idx_${name}_sync_group_updated ON $name (sync_group, updated_at)',
      'CREATE UNIQUE INDEX idx_${name}_entity ON $name (entity_id)',
    ],
    'listRule': 'sync_group = @request.auth.id',
    'viewRule': 'sync_group = @request.auth.id',
    'createRule': 'sync_group = @request.auth.id',
    'updateRule': 'sync_group = @request.auth.id',
    'deleteRule': 'sync_group = @request.auth.id',
  };

  const collectionNames = [
    'tasks',
    'categories',
    'templates',
    'template_blocks',
    'saved_searches',
    'day_blocks',
  ];

  final token = await authenticate();
  final request = await client.putUrl(
    Uri.parse('$baseUrl/api/collections/import'),
  );
  request.headers.contentType = ContentType.json;
  request.headers.set('Authorization', token);
  request.write(
    jsonEncode({
      'collections': [
        {
          'name': 'sync_groups',
          'type': 'auth',
          'fields': [],
          'passwordAuth': {'enabled': true, 'identityFields': ['username']},
        },
        for (final name in collectionNames) baseCollection(name),
      ],
      'deleteMissing': false,
    }),
  );
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200) {
    throw StateError('Import failed (${response.statusCode}): $body');
  }
  stdout.writeln('PocketBase collections created.');
  client.close();
}
```

Note for the executor: this targets PocketBase 0.28's collection-import shape (`fields`, not the pre-0.23 `schema`; `_superusers` auth, not `_admins`). If `docker compose exec pocketbase /pb/pocketbase --version` reports a materially different version and the import call fails, open `http://localhost:8090/_/` and create the same six collections plus `sync_groups` by hand through the admin UI, matching the fields/rules above — the rest of this plan only depends on the resulting field names (`entity_id`, `sync_group`, `updated_at`, `deleted`, `data`) and API rules, not on how they got created.

- [ ] **Step 5: Run the setup script and verify**

Run: `dart run scripts/setup_pocketbase.dart http://localhost:8090 dev@taskframe.local dev-password-change-me`
Expected: `PocketBase collections created.`; `http://localhost:8090/_/` (admin UI) shows all 7 collections.

- [ ] **Step 6: Commit**

```bash
git add pocketbase/Dockerfile docker-compose.yml scripts/setup_pocketbase.dart
git commit -m "feat: add self-hosted PocketBase service and collection setup"
```

---

### Task 2: Generic cursor/pairing storage on `AppSettingsRepository`

**Files:**
- Modify: `lib/core/storage/app_settings_repository.dart`
- Test: `test/unit/app_settings_repository_test.dart`

**Interfaces:**
- Produces: `AppSettingsRepository.getValue(String key) -> Future<String?>` and `setValue(String key, String value) -> Future<void>`, on both `InMemoryAppSettingsRepository` and `SembastAppSettingsRepository`. Later tasks store sync cursors as keys like `sync_push_tasks`/`sync_pull_tasks` and pairing state as `sync_group_identity`/`sync_group_token` through these two methods.

- [ ] **Step 1: Write the failing tests**

```dart
// test/unit/app_settings_repository_test.dart — add to the existing file
test('getValue returns null for an unset key', () async {
  final repository = InMemoryAppSettingsRepository();
  expect(await repository.getValue('missing'), isNull);
});

test('setValue then getValue round-trips', () async {
  final repository = InMemoryAppSettingsRepository();
  await repository.setValue('sync_pull_tasks', '2026-09-15T00:00:00.000Z');
  expect(
    await repository.getValue('sync_pull_tasks'),
    '2026-09-15T00:00:00.000Z',
  );
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/unit/app_settings_repository_test.dart`
Expected: FAIL — `getValue`/`setValue` not defined on `InMemoryAppSettingsRepository`.

- [ ] **Step 3: Implement**

```dart
// lib/core/storage/app_settings_repository.dart — extend the interface and both implementations
abstract class AppSettingsRepository {
  Future<DateTime?> getInstallHintDismissedAt();
  Future<void> setInstallHintDismissedAt(DateTime time);

  /// A single stored string value, e.g. a sync cursor or pairing
  /// identity, keyed by [key]. `null` when never set.
  Future<String?> getValue(String key);

  /// Stores [value] under [key], overwriting any previous value.
  Future<void> setValue(String key, String value);
}

class InMemoryAppSettingsRepository implements AppSettingsRepository {
  DateTime? _dismissedAt;
  final Map<String, String> _values = {};

  @override
  Future<DateTime?> getInstallHintDismissedAt() async => _dismissedAt;

  @override
  Future<void> setInstallHintDismissedAt(DateTime time) async {
    _dismissedAt = time;
  }

  @override
  Future<String?> getValue(String key) async => _values[key];

  @override
  Future<void> setValue(String key, String value) async {
    _values[key] = value;
  }
}

class SembastAppSettingsRepository implements AppSettingsRepository {
  new(this._db);

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
    await settingsStore.record(_key).put(_db, {
      'value': time.toIso8601String(),
    });
  }

  @override
  Future<String?> getValue(String key) async {
    final record = await settingsStore.record(key).get(_db);
    return record?['value'] as String?;
  }

  @override
  Future<void> setValue(String key, String value) async {
    await settingsStore.record(key).put(_db, {'value': value});
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/unit/app_settings_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/storage/app_settings_repository.dart test/unit/app_settings_repository_test.dart
git commit -m "feat: add generic key-value storage to AppSettingsRepository"
```

---

### Task 3: `Task` model + repository — `updatedAt`/`deleted`, soft delete

**Files:**
- Modify: `lib/features/task/models/task.dart`
- Modify: `lib/features/task/data/sembast_task_repository.dart`
- Test: `test/unit/task_test.dart`, `test/unit/sembast_task_repository_test.dart`

**Interfaces:**
- Produces: `Task.updatedAt -> DateTime`, `Task.deleted -> bool` (default `false`); `Task.toMap()`/`Task.fromMap()` include both. `SembastTaskRepository.load()` excludes soft-deleted records; `.delete()` soft-deletes (record stays in the store with `deleted: true`) instead of removing it — this is what later tasks' `SyncCollection` for `tasksStore` pushes as a tombstone.

- [ ] **Step 1: Write the failing tests**

```dart
// test/unit/task_test.dart — add
test('toMap/fromMap round-trip updatedAt and deleted', () {
  final updatedAt = DateTime.utc(2026, 9, 15, 12);
  final task = Task(
    id: 't1',
    title: 'Buy milk',
    updatedAt: updatedAt,
    deleted: true,
  );
  final restored = Task.fromMap(task.toMap());
  expect(restored.updatedAt, updatedAt);
  expect(restored.deleted, isTrue);
});

test('fromMap defaults deleted to false and updatedAt to epoch when absent', () {
  final restored = Task.fromMap({
    'id': 't1',
    'title': 'Buy milk',
    'closed': false,
    'categoryId': Category.defaultId,
  });
  expect(restored.deleted, isFalse);
  expect(restored.updatedAt, DateTime.fromMillisecondsSinceEpoch(0));
});
```

```dart
// test/unit/sembast_task_repository_test.dart — add
test('delete soft-deletes: record stays but is excluded from load', () async {
  final added = await repository.add(title: 'Buy milk');

  await repository.delete(added);

  expect(await repository.load(), isEmpty);
  final record = await tasksStore.record(added.id).get(db);
  expect(record, isNotNull);
  expect(record!['deleted'], isTrue);
});

test('add and update stamp updatedAt', () async {
  final added = await repository.add(title: 'Buy milk');
  expect(added.updatedAt, isNotNull);

  final updated = await repository.update(added, title: 'Buy oat milk');
  expect(updated.updatedAt.isAtSameMomentAs(added.updatedAt), isFalse);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/unit/task_test.dart test/unit/sembast_task_repository_test.dart`
Expected: FAIL — `updatedAt`/`deleted` not defined on `Task`.

- [ ] **Step 3: Update the model**

```dart
// lib/features/task/models/task.dart
class Task {
  const new({
    required this.id,
    required this.title,
    this.closed = false,
    this.categoryId = Category.defaultId,
    this.tags = const [],
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? const _Epoch();

  factory fromMap(Map<String, Object?> map) => Task(
    id: map['id']! as String,
    title: map['title']! as String,
    closed: map['closed']! as bool,
    categoryId: map['categoryId']! as String,
    tags: [for (final tag in map['tags'] as List? ?? const []) tag as String],
    updatedAt: map['updatedAt'] == null
        ? null
        : DateTime.parse(map['updatedAt']! as String),
    deleted: map['deleted'] as bool? ?? false,
  );

  final String id;
  final String title;
  final bool closed;
  final String categoryId;
  final List<String> tags;

  /// When this task was last changed. Defaults to the Unix epoch for
  /// records written before sync existed, so they always lose an
  /// LWW comparison against a genuinely newer edit.
  final DateTime updatedAt;

  /// Soft-delete tombstone: `true` once removed, so the deletion can
  /// propagate to other devices instead of being silently resurrected.
  final bool deleted;

  Task copyWith({
    String? title,
    bool? closed,
    String? categoryId,
    List<String>? tags,
    DateTime? updatedAt,
    bool? deleted,
  }) => Task(
    id: id,
    title: title ?? this.title,
    closed: closed ?? this.closed,
    categoryId: categoryId ?? this.categoryId,
    tags: tags ?? this.tags,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'closed': closed,
    'categoryId': categoryId,
    'tags': tags,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
  };
}
```

Replace the `const _Epoch()` default trick with a plain static constant instead — Dart doesn't need a helper class for this:

```dart
  const new({
    required this.id,
    required this.title,
    this.closed = false,
    this.categoryId = Category.defaultId,
    this.tags = const [],
    this.updatedAt = _epoch,
    this.deleted = false,
  });

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
```

(Use this second form — it's simpler than a wrapper class. Apply the same pattern in every other model touched by this plan.)

- [ ] **Step 4: Update the repository's `add`/`update`/`delete`/`load`**

```dart
// lib/features/task/data/sembast_task_repository.dart
@override
Future<List<Task>> load() async {
  final finder = Finder(
    filter: Filter.notEquals('deleted', true),
    sortOrders: [SortOrder('order')],
  );
  final records = await tasksStore.find(_db, finder: finder);
  return [for (final record in records) Task.fromMap(record.value)];
}

@override
Future<Task> add({required String title, String? categoryId}) async {
  final task = Task(
    id: _uuid.v4(),
    title: title,
    categoryId: categoryId ?? Category.defaultId,
    updatedAt: DateTime.now().toUtc(),
  );
  await tasksStore.record(task.id).put(_db, {
    ...task.toMap(),
    'order': DateTime.now().microsecondsSinceEpoch,
  });
  return task;
}

@override
Future<Task> update(
  Task task, {
  String? title,
  bool? closed,
  String? categoryId,
  List<String>? tags,
}) async {
  final existingRecord = await tasksStore.record(task.id).get(_db);
  final current = existingRecord == null
      ? task
      : Task.fromMap(existingRecord);
  final updated = current.copyWith(
    title: title,
    closed: closed,
    categoryId: categoryId,
    tags: tags,
    updatedAt: DateTime.now().toUtc(),
  );
  final order =
      existingRecord?['order'] ?? DateTime.now().microsecondsSinceEpoch;
  await tasksStore.record(updated.id).put(_db, {
    ...updated.toMap(),
    'order': order,
  });
  return updated;
}

@override
Future<void> delete(Task task) async {
  final existingRecord = await tasksStore.record(task.id).get(_db);
  final current = existingRecord == null
      ? task
      : Task.fromMap(existingRecord);
  final tombstone = current.copyWith(
    deleted: true,
    updatedAt: DateTime.now().toUtc(),
  );
  await tasksStore.record(task.id).put(_db, {
    ...tombstone.toMap(),
    'order': existingRecord?['order'] ?? 0,
  });
}
```

Note the id generator changed from `_uuid.v4()` unconditionally already used — no change there, just confirming `add` keeps using it (this snippet repeats the surrounding line only for context; don't duplicate the `const _uuid = Uuid();` top-level declaration, it already exists in the file).

- [ ] **Step 5: Run to verify they pass**

Run: `flutter test test/unit/task_test.dart test/unit/sembast_task_repository_test.dart`
Expected: PASS

- [ ] **Step 6: Run the full unit suite to catch ripple effects**

Run: `flutter test test/unit`
Expected: PASS — `task_providers_test.dart`/`task_repository_test.dart` (against `InMemoryTaskRepository`, unaffected by this task) should be unaffected since `InMemoryTaskRepository` isn't synced and its `delete` stays a hard delete (in-memory repos are test/dev-only stand-ins never wired to sync — see Task 10).

- [ ] **Step 7: Commit**

```bash
git add lib/features/task/models/task.dart lib/features/task/data/sembast_task_repository.dart test/unit/task_test.dart test/unit/sembast_task_repository_test.dart
git commit -m "feat: add updatedAt/deleted to Task, soft-delete in SembastTaskRepository"
```

---

### Task 4: `Category` model + repository — same treatment

**Files:**
- Modify: `lib/features/category/models/category.dart`
- Modify: `lib/features/category/data/sembast_category_repository.dart`
- Test: `test/unit/category_test.dart`, `test/unit/sembast_category_repository_test.dart`

**Interfaces:**
- Produces: `Category.updatedAt`/`Category.deleted`, same shape as Task's (Task 3). `SembastCategoryRepository.load()` excludes soft-deleted; `.delete()` soft-deletes. The default category is never deleted today (`delete` already no-ops on `isDefault`) — that behavior is unchanged.

- [ ] **Step 1: Write the failing tests**

```dart
// test/unit/category_test.dart — add
test('toMap/fromMap round-trip updatedAt and deleted', () {
  final updatedAt = DateTime.utc(2026, 9, 15, 12);
  const base = Category(id: 'c1', name: 'Work', colorValue: 0xFF000000);
  final category = base.copyWith()
    ..let((c) {}); // placeholder removed below — see actual test
  final withStamp = Category(
    id: 'c1',
    name: 'Work',
    colorValue: 0xFF000000,
    updatedAt: updatedAt,
    deleted: true,
  );
  final restored = Category.fromMap(withStamp.toMap());
  expect(restored.updatedAt, updatedAt);
  expect(restored.deleted, isTrue);
});
```

Remove the stray `let`/placeholder line above — write the test directly as:

```dart
// test/unit/category_test.dart — add (final version, use this one)
test('toMap/fromMap round-trip updatedAt and deleted', () {
  final updatedAt = DateTime.utc(2026, 9, 15, 12);
  final category = Category(
    id: 'c1',
    name: 'Work',
    colorValue: 0xFF000000,
    updatedAt: updatedAt,
    deleted: true,
  );
  final restored = Category.fromMap(category.toMap());
  expect(restored.updatedAt, updatedAt);
  expect(restored.deleted, isTrue);
});
```

```dart
// test/unit/sembast_category_repository_test.dart — add
test('delete soft-deletes a non-default category', () async {
  final added = await repository.add(name: 'Work', colorValue: 0xFF000000);

  await repository.delete(added);

  expect(await repository.load(), hasLength(1)); // default only
  final record = await categoriesStore.record(added.id).get(db);
  expect(record!['deleted'], isTrue);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/unit/category_test.dart test/unit/sembast_category_repository_test.dart`
Expected: FAIL — `updatedAt`/`deleted` not defined.

- [ ] **Step 3: Update the model**

```dart
// lib/features/category/models/category.dart
class Category {
  const new({
    required this.id,
    required this.name,
    required this.colorValue,
    this.emoji,
    this.updatedAt = _epoch,
    this.deleted = false,
  });

  factory fromMap(Map<String, Object?> map) => Category(
    id: map['id']! as String,
    name: map['name']! as String,
    colorValue: map['colorValue']! as int,
    emoji: map['emoji'] as String?,
    updatedAt: map['updatedAt'] == null
        ? _epoch
        : DateTime.parse(map['updatedAt']! as String),
    deleted: map['deleted'] as bool? ?? false,
  );

  static const String defaultId = '0';
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final int colorValue;
  final String? emoji;
  final DateTime updatedAt;
  final bool deleted;

  bool get isDefault => id == defaultId;

  String formatTitle(String title) => emoji == null ? title : '$emoji $title';

  Category copyWith({
    String? name,
    int? colorValue,
    String? emoji,
    DateTime? updatedAt,
    bool? deleted,
  }) => Category(
    id: id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    emoji: emoji ?? this.emoji,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'emoji': emoji,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
  };
}
```

- [ ] **Step 4: Update the repository**

```dart
// lib/features/category/data/sembast_category_repository.dart
@override
Future<List<Category>> load() async {
  final finder = Finder(
    filter: Filter.notEquals('deleted', true),
    sortOrders: [SortOrder('order')],
  );
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
    updatedAt: DateTime.now().toUtc(),
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
  final updated = (current.isDefault
          ? current.copyWith(colorValue: colorValue)
          : current.copyWith(
              name: name,
              colorValue: colorValue,
              emoji: emoji,
            ))
      .copyWith(updatedAt: DateTime.now().toUtc());
  final order =
      existingRecord?['order'] ??
      (current.isDefault ? 0 : DateTime.now().microsecondsSinceEpoch);
  await categoriesStore.record(updated.id).put(_db, {
    ...updated.toMap(),
    'order': order,
  });
  return updated;
}

@override
Future<void> delete(Category category) async {
  if (category.isDefault) return;
  final existingRecord = await categoriesStore.record(category.id).get(_db);
  final current = existingRecord == null
      ? category
      : Category.fromMap(existingRecord);
  final tombstone = current.copyWith(
    deleted: true,
    updatedAt: DateTime.now().toUtc(),
  );
  await categoriesStore.record(category.id).put(_db, {
    ...tombstone.toMap(),
    'order': existingRecord?['order'] ?? 0,
  });
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `flutter test test/unit/category_test.dart test/unit/sembast_category_repository_test.dart test/unit`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/category/models/category.dart lib/features/category/data/sembast_category_repository.dart test/unit/category_test.dart test/unit/sembast_category_repository_test.dart
git commit -m "feat: add updatedAt/deleted to Category, soft-delete in SembastCategoryRepository"
```

---

### Task 5: `Template` model + `SembastTemplateRepository` — same treatment

**Files:**
- Modify: `lib/features/template/models/template.dart`
- Modify: `lib/features/template/data/sembast_template_repository.dart` (only `SembastTemplateRepository` in this task — `SembastTemplateBlocksRepository` is Task 6)
- Test: `test/unit/template_test.dart`, `test/unit/sembast_template_repository_test.dart`

**Interfaces:**
- Produces: `Template.updatedAt`/`Template.deleted`, same shape as Task 3/4. `SembastTemplateRepository.load()` excludes soft-deleted; `.delete()` soft-deletes.

- [ ] **Step 1: Write the failing tests**

```dart
// test/unit/template_test.dart — add
test('toMap/fromMap round-trip updatedAt and deleted', () {
  final updatedAt = DateTime.utc(2026, 9, 15, 12);
  final template = Template(
    id: 'tpl1',
    name: 'Weekday',
    updatedAt: updatedAt,
    deleted: true,
  );
  final restored = Template.fromMap(template.toMap());
  expect(restored.updatedAt, updatedAt);
  expect(restored.deleted, isTrue);
});
```

```dart
// test/unit/sembast_template_repository_test.dart — add, in the SembastTemplateRepository group
test('delete soft-deletes: record stays but is excluded from load', () async {
  final added = await repository.add(name: 'Weekday');

  await repository.delete(added);

  expect(await repository.load(), isEmpty);
  final record = await templatesStore.record(added.id).get(db);
  expect(record!['deleted'], isTrue);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/unit/template_test.dart test/unit/sembast_template_repository_test.dart`
Expected: FAIL

- [ ] **Step 3: Update the model**

```dart
// lib/features/template/models/template.dart
class Template {
  const new({
    required this.id,
    required this.name,
    this.updatedAt = _epoch,
    this.deleted = false,
  });

  factory fromMap(Map<String, Object?> map) => Template(
    id: map['id']! as String,
    name: map['name']! as String,
    updatedAt: map['updatedAt'] == null
        ? _epoch
        : DateTime.parse(map['updatedAt']! as String),
    deleted: map['deleted'] as bool? ?? false,
  );

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final DateTime updatedAt;
  final bool deleted;

  Template copyWith({String? name, DateTime? updatedAt, bool? deleted}) =>
      Template(
        id: id,
        name: name ?? this.name,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
  };

  @override
  bool operator ==(Object other) =>
      other is Template &&
      other.id == id &&
      other.name == name &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(id, name, updatedAt, deleted);
}
```

- [ ] **Step 4: Update `SembastTemplateRepository`**

```dart
// lib/features/template/data/sembast_template_repository.dart — SembastTemplateRepository only
@override
Future<List<Template>> load() async {
  final finder = Finder(
    filter: Filter.notEquals('deleted', true),
    sortOrders: [SortOrder('order')],
  );
  final records = await templatesStore.find(_db, finder: finder);
  return [for (final record in records) Template.fromMap(record.value)];
}

@override
Future<Template> add({required String name}) async {
  final template = Template(
    id: _uuid.v4(),
    name: name,
    updatedAt: DateTime.now().toUtc(),
  );
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
  final renamed = template.copyWith(
    name: name,
    updatedAt: DateTime.now().toUtc(),
  );
  await templatesStore.record(renamed.id).put(_db, {
    ...renamed.toMap(),
    'order': existingRecord['order'],
  });
  return renamed;
}

@override
Future<void> delete(Template template) async {
  final existingRecord = await templatesStore.record(template.id).get(_db);
  final current = existingRecord == null
      ? template
      : Template.fromMap(existingRecord);
  final tombstone = current.copyWith(
    deleted: true,
    updatedAt: DateTime.now().toUtc(),
  );
  await templatesStore.record(template.id).put(_db, {
    ...tombstone.toMap(),
    'order': existingRecord?['order'] ?? 0,
  });
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `flutter test test/unit/template_test.dart test/unit/sembast_template_repository_test.dart test/unit`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/template/models/template.dart lib/features/template/data/sembast_template_repository.dart test/unit/template_test.dart test/unit/sembast_template_repository_test.dart
git commit -m "feat: add updatedAt/deleted to Template, soft-delete in SembastTemplateRepository"
```

---

### Task 6: `TimeObject` model + day/template block repositories — same treatment

**Files:**
- Modify: `lib/features/day/models/time_object.dart` (shared by day blocks and template blocks)
- Modify: `lib/features/day/data/sembast_day_blocks_repository.dart`
- Modify: `lib/features/template/data/sembast_template_repository.dart` (`SembastTemplateBlocksRepository` this time)
- Test: `test/unit/time_object_test.dart`, `test/unit/sembast_day_blocks_repository_test.dart`, `test/unit/sembast_template_repository_test.dart`

**Interfaces:**
- Produces: `TimeObject.updatedAt`/`TimeObject.deleted`. Both `SembastDayBlocksRepository` and `SembastTemplateBlocksRepository` exclude soft-deleted records from `load`/`load(templateId)` and soft-delete instead of hard-delete in `delete`. `move`/`update` both stamp `updatedAt`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/unit/time_object_test.dart — add
test('toMap/fromMap round-trip updatedAt and deleted', () {
  final updatedAt = DateTime.utc(2026, 9, 15, 12);
  final block = TimeObject(
    id: 'b1',
    title: 'Work',
    start: DateTime(2026, 9, 15, 9),
    end: DateTime(2026, 9, 15, 10),
    kind: BlockKind.frame,
    locked: false,
    updatedAt: updatedAt,
    deleted: true,
  );
  final restored = TimeObject.fromMap(block.toMap());
  expect(restored.updatedAt, updatedAt);
  expect(restored.deleted, isTrue);
});
```

```dart
// test/unit/sembast_day_blocks_repository_test.dart — add
test('delete soft-deletes: block stays in the store but excluded from load', () async {
  final today = DateTime.now();
  final added = await repository.add(
    today,
    start: DateTime(today.year, today.month, today.day, 9),
    end: DateTime(today.year, today.month, today.day, 10),
    kind: BlockKind.frame,
  );

  await repository.delete(added, date: today);

  expect(await repository.load(today), isEmpty);
  final record = await dayBlocksStore.record(added.id).get(db);
  expect(record!['deleted'], isTrue);
});
```

```dart
// test/unit/sembast_template_repository_test.dart — add, in the SembastTemplateBlocksRepository group
test('delete soft-deletes: block stays in the store but excluded from load', () async {
  final added = await blocksRepository.add(
    'tpl1',
    start: DateTime(2026, 1, 1, 9),
    end: DateTime(2026, 1, 1, 10),
    kind: BlockKind.frame,
  );

  await blocksRepository.delete(added, templateId: 'tpl1');

  expect(await blocksRepository.load('tpl1'), isEmpty);
  final record = await templateBlocksStore.record(added.id).get(db);
  expect(record!['deleted'], isTrue);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/unit/time_object_test.dart test/unit/sembast_day_blocks_repository_test.dart test/unit/sembast_template_repository_test.dart`
Expected: FAIL

- [ ] **Step 3: Update the model**

```dart
// lib/features/day/models/time_object.dart
class TimeObject {
  new({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.kind,
    required this.locked,
    this.categoryId = Category.defaultId,
    this.updatedAt = _epoch,
    this.deleted = false,
  }) : assert(_isOnGrid(start), 'start must be on the 15-minute grid'),
       assert(_isOnGrid(end), 'end must be on the 15-minute grid'),
       assert(end.isAfter(start), 'end must be after start');

  factory fromMap(Map<String, Object?> map) => TimeObject(
    id: map['id']! as String,
    title: map['title']! as String,
    start: DateTime.parse(map['start']! as String),
    end: DateTime.parse(map['end']! as String),
    kind: BlockKind.values.byName(map['kind']! as String),
    locked: map['locked']! as bool,
    categoryId: map['categoryId']! as String,
    updatedAt: map['updatedAt'] == null
        ? _epoch
        : DateTime.parse(map['updatedAt']! as String),
    deleted: map['deleted'] as bool? ?? false,
  );

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final BlockKind kind;
  final bool locked;
  final String categoryId;
  final DateTime updatedAt;
  final bool deleted;

  static bool _isOnGrid(DateTime time) =>
      time.second == 0 &&
      time.millisecond == 0 &&
      time.microsecond == 0 &&
      time.minute % 15 == 0;

  bool overlaps(DateTime start, DateTime end) =>
      start.isBefore(this.end) && end.isAfter(this.start);

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'kind': kind.name,
    'locked': locked,
    'categoryId': categoryId,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
  };
}
```

- [ ] **Step 4: Update `SembastDayBlocksRepository`**

```dart
// lib/features/day/data/sembast_day_blocks_repository.dart
@override
Future<List<TimeObject>> load(DateTime date) async {
  final finder = Finder(
    filter: Filter.and([
      Filter.equals('dateKey', dateKeyFor(date)),
      Filter.notEquals('deleted', true),
    ]),
    sortOrders: [SortOrder('start')],
  );
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
    title: title ?? '',
    start: start,
    end: end,
    kind: kind,
    locked: false,
    categoryId: categoryId ?? Category.defaultId,
    updatedAt: DateTime.now().toUtc(),
  );
  await dayBlocksStore.record(block.id).put(_db, {
    ...block.toMap(),
    'dateKey': dateKeyFor(date),
  });
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
    updatedAt: DateTime.now().toUtc(),
  );
  await dayBlocksStore.record(block.id).put(_db, {
    ...moved.toMap(),
    'dateKey': dateKeyFor(toDate),
  });
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
    updatedAt: DateTime.now().toUtc(),
  );
  await dayBlocksStore.record(block.id).put(_db, {
    ...updated.toMap(),
    'dateKey': dateKeyFor(date),
  });
  return updated;
}

@override
Future<void> delete(TimeObject block, {required DateTime date}) async {
  final existingRecord = await dayBlocksStore.record(block.id).get(_db);
  final current = existingRecord == null
      ? block
      : TimeObject.fromMap(existingRecord);
  await dayBlocksStore.record(block.id).put(_db, {
    ...current.toMap(),
    'deleted': true,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'dateKey': existingRecord?['dateKey'] ?? dateKeyFor(date),
  });
}
```

- [ ] **Step 5: Update `SembastTemplateBlocksRepository`**

```dart
// lib/features/template/data/sembast_template_repository.dart — SembastTemplateBlocksRepository only
@override
Future<List<TimeObject>> load(String templateId) async {
  final finder = Finder(
    filter: Filter.and([
      Filter.equals('templateId', templateId),
      Filter.notEquals('deleted', true),
    ]),
    sortOrders: [SortOrder('start')],
  );
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
    title: title ?? '',
    start: start,
    end: end,
    kind: kind,
    locked: false,
    categoryId: categoryId ?? Category.defaultId,
    updatedAt: DateTime.now().toUtc(),
  );
  await templateBlocksStore.record(block.id).put(_db, {
    ...block.toMap(),
    'templateId': templateId,
  });
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
    updatedAt: DateTime.now().toUtc(),
  );
  await templateBlocksStore.record(block.id).put(_db, {
    ...moved.toMap(),
    'templateId': toTemplateId,
  });
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
    updatedAt: DateTime.now().toUtc(),
  );
  final existing = await templateBlocksStore.record(block.id).get(_db);
  if (existing == null) return updated;
  await templateBlocksStore.record(block.id).put(_db, {
    ...updated.toMap(),
    'templateId': templateId,
  });
  return updated;
}

@override
Future<void> delete(TimeObject block, {required String templateId}) async {
  final existingRecord = await templateBlocksStore.record(block.id).get(_db);
  final current = existingRecord == null
      ? block
      : TimeObject.fromMap(existingRecord);
  await templateBlocksStore.record(block.id).put(_db, {
    ...current.toMap(),
    'deleted': true,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'templateId': existingRecord?['templateId'] ?? templateId,
  });
}

@override
Future<void> deleteAll(String templateId) async {
  final finder = Finder(filter: Filter.equals('templateId', templateId));
  final records = await templateBlocksStore.find(_db, finder: finder);
  for (final record in records) {
    final current = TimeObject.fromMap(record.value);
    await templateBlocksStore.record(record.key).put(_db, {
      ...current.toMap(),
      'deleted': true,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'templateId': templateId,
    });
  }
}
```

Note `deleteAll` changes from a bulk `store.delete(finder:)` to per-record soft-delete — deleting a template now tombstones its blocks individually so each one's deletion syncs, rather than silently vanishing from the store.

- [ ] **Step 6: Run to verify they pass**

Run: `flutter test test/unit/time_object_test.dart test/unit/sembast_day_blocks_repository_test.dart test/unit/sembast_template_repository_test.dart test/unit`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/features/day/models/time_object.dart lib/features/day/data/sembast_day_blocks_repository.dart lib/features/template/data/sembast_template_repository.dart test/unit/time_object_test.dart test/unit/sembast_day_blocks_repository_test.dart test/unit/sembast_template_repository_test.dart
git commit -m "feat: add updatedAt/deleted to TimeObject, soft-delete in day/template block repositories"
```

---

### Task 7: `SavedSearch` model + repository — same treatment

**Files:**
- Modify: `lib/features/saved_search/models/saved_search.dart`
- Modify: `lib/features/saved_search/data/sembast_saved_search_repository.dart`
- Test: `test/unit/saved_search_test.dart`, `test/unit/sembast_saved_search_repository_test.dart`

**Interfaces:**
- Produces: `SavedSearch.updatedAt`/`SavedSearch.deleted`, same shape as prior tasks. `SembastSavedSearchRepository.load()` excludes soft-deleted; `.delete()` soft-deletes; `.reorder()` also stamps `updatedAt` since it changes `order`, which is part of the synced payload.

- [ ] **Step 1: Write the failing tests**

```dart
// test/unit/saved_search_test.dart — add
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
```

```dart
// test/unit/sembast_saved_search_repository_test.dart — add
test('delete soft-deletes: view stays but is excluded from load', () async {
  final added = await repository.add(name: 'Work', query: '#work');

  await repository.delete(added);

  expect(await repository.load(), isEmpty);
  final record = await savedSearchesStore.record(added.id).get(db);
  expect(record!['deleted'], isTrue);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/unit/saved_search_test.dart test/unit/sembast_saved_search_repository_test.dart`
Expected: FAIL

- [ ] **Step 3: Update the model**

```dart
// lib/features/saved_search/models/saved_search.dart
@immutable
class SavedSearch {
  const new({
    required this.id,
    required this.name,
    required this.query,
    required this.order,
    this.updatedAt = _epoch,
    this.deleted = false,
  });

  factory fromMap(Map<String, Object?> map) => SavedSearch(
    id: map['id']! as String,
    name: map['name']! as String,
    query: map['query']! as String,
    order: map['order']! as int,
    updatedAt: map['updatedAt'] == null
        ? _epoch
        : DateTime.parse(map['updatedAt']! as String),
    deleted: map['deleted'] as bool? ?? false,
  );

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final String query;
  final int order;
  final DateTime updatedAt;
  final bool deleted;

  SavedSearch copyWith({
    String? name,
    String? query,
    int? order,
    DateTime? updatedAt,
    bool? deleted,
  }) => SavedSearch(
    id: id,
    name: name ?? this.name,
    query: query ?? this.query,
    order: order ?? this.order,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'query': query,
    'order': order,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
  };

  @override
  bool operator ==(Object other) =>
      other is SavedSearch &&
      other.id == id &&
      other.name == name &&
      other.query == query &&
      other.order == order &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode =>
      Object.hash(id, name, query, order, updatedAt, deleted);
}
```

- [ ] **Step 4: Update the repository**

```dart
// lib/features/saved_search/data/sembast_saved_search_repository.dart
@override
Future<List<SavedSearch>> load() async {
  final finder = Finder(
    filter: Filter.notEquals('deleted', true),
    sortOrders: [SortOrder('order')],
  );
  final records = await savedSearchesStore.find(_db, finder: finder);
  return [for (final record in records) SavedSearch.fromMap(record.value)];
}

@override
Future<SavedSearch> add({required String name, required String query}) async {
  final existing = await load();
  final nextOrder = existing.isEmpty
      ? 0
      : existing.map((v) => v.order).reduce((a, b) => a > b ? a : b) + 1;
  final view = SavedSearch(
    id: _uuid.v4(),
    name: name,
    query: query,
    order: nextOrder,
    updatedAt: DateTime.now().toUtc(),
  );
  await savedSearchesStore.record(view.id).put(_db, view.toMap());
  return view;
}

@override
Future<SavedSearch> rename(SavedSearch view, String name) async {
  final updated = view.copyWith(name: name, updatedAt: DateTime.now().toUtc());
  await savedSearchesStore.record(updated.id).put(_db, updated.toMap());
  return updated;
}

@override
Future<void> delete(SavedSearch view) async {
  final tombstone = view.copyWith(
    deleted: true,
    updatedAt: DateTime.now().toUtc(),
  );
  await savedSearchesStore.record(view.id).put(_db, tombstone.toMap());
}

@override
Future<void> reorder(List<SavedSearch> orderedViews) async {
  for (var i = 0; i < orderedViews.length; i++) {
    final updated = orderedViews[i].copyWith(
      order: i,
      updatedAt: DateTime.now().toUtc(),
    );
    await savedSearchesStore.record(updated.id).put(_db, updated.toMap());
  }
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `flutter test test/unit/saved_search_test.dart test/unit/sembast_saved_search_repository_test.dart test/unit`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/saved_search/models/saved_search.dart lib/features/saved_search/data/sembast_saved_search_repository.dart test/unit/saved_search_test.dart test/unit/sembast_saved_search_repository_test.dart
git commit -m "feat: add updatedAt/deleted to SavedSearch, soft-delete in SembastSavedSearchRepository"
```

---

### Task 8: `SyncCollection` config + generic `SyncEngine`

**Files:**
- Create: `lib/core/sync/sync_collection.dart`
- Create: `lib/core/sync/sync_engine.dart`
- Test: `test/unit/sync_engine_test.dart`

**Interfaces:**
- Consumes: sembast `StoreRef<String, Map<String, Object?>>`s from `app_database.dart` (`tasksStore`, `categoriesStore`, `templatesStore`, `templateBlocksStore`, `savedSearchesStore`, `dayBlocksStore`); `AppSettingsRepository.getValue`/`setValue` (Task 2).
- Produces: `SyncCollection` (`name`, `store`) and `syncCollections` (the fixed list of six, for Task 10's wiring). `SyncEngine` with constructor `SyncEngine({required Database db, required AppSettingsRepository settings, required SyncBackend backend})` and method `Future<void> syncAll(List<SyncCollection> collections)`. `SyncBackend` is the abstract seam this task defines so the engine is testable without PocketBase; Task 9's `PocketBaseSyncClient` implements it.

- [ ] **Step 1: Define `SyncCollection`**

```dart
// lib/core/sync/sync_collection.dart
import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';

/// One synced sembast store, paired with the PocketBase collection name
/// it syncs against. [SyncEngine.syncAll] iterates a list of these.
class SyncCollection {
  const SyncCollection({required this.name, required this.store});

  /// The PocketBase collection name — also the key prefix for this
  /// collection's push/pull cursors.
  final String name;

  final StoreRef<String, Map<String, Object?>> store;
}

/// The six sembast stores synced by this app.
final List<SyncCollection> syncCollections = [
  SyncCollection(name: 'tasks', store: tasksStore),
  SyncCollection(name: 'categories', store: categoriesStore),
  SyncCollection(name: 'templates', store: templatesStore),
  SyncCollection(name: 'template_blocks', store: templateBlocksStore),
  SyncCollection(name: 'saved_searches', store: savedSearchesStore),
  SyncCollection(name: 'day_blocks', store: dayBlocksStore),
];
```

- [ ] **Step 2: Write the failing tests for `SyncEngine`**

```dart
// test/unit/sync_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

/// A [SyncBackend] backed by an in-memory map, standing in for
/// PocketBase in these tests.
class FakeSyncBackend implements SyncBackend {
  final Map<String, List<Map<String, Object?>>> remote = {};

  @override
  Future<void> upsert(String collection, Map<String, Object?> record) async {
    final list = remote.putIfAbsent(collection, () => []);
    final index = list.indexWhere((r) => r['entity_id'] == record['entity_id']);
    if (index == -1) {
      list.add(record);
    } else {
      list[index] = record;
    }
  }

  @override
  Future<List<Map<String, Object?>>> listChangedSince(
    String collection,
    DateTime cursor,
  ) async {
    final list = remote[collection] ?? [];
    return [
      for (final record in list)
        if (DateTime.parse(record['updated_at']! as String).isAfter(cursor))
          record,
    ];
  }
}

void main() {
  late Database db;
  late InMemoryAppSettingsRepository settings;
  late FakeSyncBackend backend;
  late SyncEngine engine;
  const collection = SyncCollection(name: 'tasks', store: null); // overwritten below

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('test.db');
    settings = InMemoryAppSettingsRepository();
    backend = FakeSyncBackend();
    engine = SyncEngine(db: db, settings: settings, backend: backend);
  });

  final store = stringMapStoreFactory.store('things');
  final things = SyncCollection(name: 'things', store: store);

  test('pushes a locally-changed record and advances the push cursor', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'deleted': false,
    });

    await engine.syncAll([things]);

    expect(backend.remote['things'], hasLength(1));
    expect(backend.remote['things']!.single['entity_id'], 'a');
    expect(
      await settings.getValue('sync_push_things'),
      isNotNull,
    );
  });

  test('does not re-push a record already at or before the push cursor', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'deleted': false,
    });
    await engine.syncAll([things]);
    backend.remote['things']!.clear();

    await engine.syncAll([things]);

    expect(backend.remote['things'], isEmpty);
  });

  test('pulls a remote record newer than the local copy (remote wins)', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'title': 'old',
      'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'deleted': false,
    });
    backend.remote['things'] = [
      {
        'entity_id': 'a',
        'updated_at': DateTime.utc(2026, 1, 2).toIso8601String(),
        'deleted': false,
        'data': {
          'id': 'a',
          'title': 'new',
          'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
          'deleted': false,
        },
      },
    ];

    await engine.syncAll([things]);

    final local = await store.record('a').get(db);
    expect(local!['title'], 'new');
  });

  test('keeps the local record when it is newer than the remote copy', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'title': 'new-local',
      'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
      'deleted': false,
    });
    backend.remote['things'] = [
      {
        'entity_id': 'a',
        'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'deleted': false,
        'data': {
          'id': 'a',
          'title': 'old-remote',
          'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
          'deleted': false,
        },
      },
    ];

    await engine.syncAll([things]);

    final local = await store.record('a').get(db);
    expect(local!['title'], 'new-local');
  });

  test('a remote tombstone deletes the local record', () async {
    await store.record('a').put(db, {
      'id': 'a',
      'title': 'still here',
      'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'deleted': false,
    });
    backend.remote['things'] = [
      {
        'entity_id': 'a',
        'updated_at': DateTime.utc(2026, 1, 2).toIso8601String(),
        'deleted': true,
        'data': {
          'id': 'a',
          'title': 'still here',
          'updatedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
          'deleted': true,
        },
      },
    ];

    await engine.syncAll([things]);

    final local = await store.record('a').get(db);
    expect(local!['deleted'], isTrue);
  });
}
```

Remove the unused placeholder `collection` local declared with `store: null` in Step 2's setup — it was scratch work, not part of the real test file. The actual file only needs `store`/`things` as shown after it.

- [ ] **Step 3: Run to verify they fail**

Run: `flutter test test/unit/sync_engine_test.dart`
Expected: FAIL — `SyncEngine`/`SyncBackend` not defined.

- [ ] **Step 4: Implement `SyncEngine`**

```dart
// lib/core/sync/sync_engine.dart
import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/sync_collection.dart';

/// What [SyncEngine] needs from a remote backend. [PocketBaseSyncClient]
/// (see `pocketbase_sync_client.dart`) is the real implementation; tests
/// use an in-memory fake.
abstract class SyncBackend {
  /// Creates or replaces the remote record whose `entity_id` is
  /// `record['id']`, in PocketBase collection [collection]. [record] is
  /// the full local sembast map for that entity (it must contain `id`,
  /// `updatedAt`, `deleted`).
  Future<void> upsert(String collection, Map<String, Object?> record);

  /// Returns every remote record in [collection] whose `updated_at` is
  /// strictly after [cursor]. Each returned map has `entity_id`,
  /// `updated_at`, `deleted`, and `data` (the original local sembast map
  /// as pushed by [upsert]).
  Future<List<Map<String, Object?>>> listChangedSince(
    String collection,
    DateTime cursor,
  );
}

/// Pushes locally-changed records and pulls remotely-changed records for
/// each [SyncCollection], resolving conflicts by comparing `updatedAt`
/// (last-write-wins). Never throws on a single collection's failure —
/// see [syncAll].
class SyncEngine {
  SyncEngine({
    required Database db,
    required AppSettingsRepository settings,
    required SyncBackend backend,
  }) : _db = db,
       _settings = settings,
       _backend = backend;

  final Database _db;
  final AppSettingsRepository _settings;
  final SyncBackend _backend;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// Runs push then pull for every collection in [collections]. A
  /// failure syncing one collection (e.g. a network error) is swallowed
  /// so the others still get a chance — matches the spec's "push/pull
  /// fail silently, retried on the next trigger".
  Future<void> syncAll(List<SyncCollection> collections) async {
    for (final collection in collections) {
      try {
        await _push(collection);
      } on Object {
        // Best-effort; retried on the next trigger.
      }
      try {
        await _pull(collection);
      } on Object {
        // Best-effort; retried on the next trigger.
      }
    }
  }

  Future<void> _push(SyncCollection collection) async {
    final cursor = await _cursor('sync_push_${collection.name}');
    final finder = Finder(
      filter: Filter.greaterThan('updatedAt', cursor.toIso8601String()),
    );
    final records = await collection.store.find(_db, finder: finder);
    if (records.isEmpty) return;

    DateTime? maxSeen;
    for (final record in records) {
      await _backend.upsert(collection.name, record.value);
      final updatedAt = DateTime.parse(record.value['updatedAt']! as String);
      if (maxSeen == null || updatedAt.isAfter(maxSeen)) maxSeen = updatedAt;
    }
    if (maxSeen != null) {
      await _settings.setValue(
        'sync_push_${collection.name}',
        maxSeen.toIso8601String(),
      );
    }
  }

  Future<void> _pull(SyncCollection collection) async {
    final cursor = await _cursor('sync_pull_${collection.name}');
    final remoteRecords = await _backend.listChangedSince(
      collection.name,
      cursor,
    );
    if (remoteRecords.isEmpty) return;

    DateTime? maxSeen;
    for (final remote in remoteRecords) {
      final entityId = remote['entity_id']! as String;
      final remoteUpdatedAt = DateTime.parse(remote['updated_at']! as String);
      if (maxSeen == null || remoteUpdatedAt.isAfter(maxSeen)) {
        maxSeen = remoteUpdatedAt;
      }

      final localRecord = await collection.store.record(entityId).get(_db);
      final localUpdatedAt = localRecord == null
          ? _epoch
          : DateTime.parse(localRecord['updatedAt']! as String);
      if (!remoteUpdatedAt.isAfter(localUpdatedAt)) continue;

      final data = Map<String, Object?>.from(
        remote['data']! as Map<Object?, Object?>,
      );
      await collection.store.record(entityId).put(_db, data, merge: true);
    }
    if (maxSeen != null) {
      await _settings.setValue(
        'sync_pull_${collection.name}',
        maxSeen.toIso8601String(),
      );
    }
  }

  Future<DateTime> _cursor(String key) async {
    final stored = await _settings.getValue(key);
    return stored == null ? _epoch : DateTime.parse(stored);
  }
}
```

- [ ] **Step 5: Run to verify they pass**

Run: `flutter test test/unit/sync_engine_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/core/sync/sync_collection.dart lib/core/sync/sync_engine.dart test/unit/sync_engine_test.dart
git commit -m "feat: add generic SyncEngine (push/pull, last-write-wins)"
```

---

### Task 9: `PocketBaseSyncClient` — pairing + `SyncBackend` implementation

**Files:**
- Modify: `pubspec.yaml` (add `pocketbase`)
- Create: `lib/core/sync/pocketbase_sync_client.dart`
- Test: `test/unit/pocketbase_sync_client_test.dart` (pairing-code generation only — HTTP calls are covered by Task 11's integration test, not mocked here)

**Interfaces:**
- Consumes: `SyncBackend` (Task 8, implemented by this class); `AppSettingsRepository.getValue`/`setValue` (Task 2, for storing the pairing identity/token).
- Produces: `PocketBaseSyncClient` implementing `SyncBackend`, plus `Future<String> createGroup()` (returns the new pairing code) and `Future<void> joinGroup(String code)`. `generatePairingCode()` (a standalone, unit-testable function) is what `createGroup` uses.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add pocketbase`
Expected: `pubspec.yaml` gains a `pocketbase: ^<resolved version>` line; `flutter pub get` succeeds.

- [ ] **Step 2: Write the failing test for pairing code generation**

```dart
// test/unit/pocketbase_sync_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';

void main() {
  test('generatePairingCode returns 6 uppercase alphanumeric characters', () {
    final code = generatePairingCode();
    expect(code, hasLength(6));
    expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(code), isTrue);
  });

  test('generatePairingCode is not constant across calls', () {
    final codes = {for (var i = 0; i < 20; i++) generatePairingCode()};
    expect(codes.length, greaterThan(1));
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/unit/pocketbase_sync_client_test.dart`
Expected: FAIL — `generatePairingCode` not defined.

- [ ] **Step 4: Implement**

```dart
// lib/core/sync/pocketbase_sync_client.dart
import 'dart:math';

import 'package:pocketbase/pocketbase.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I

/// A random 6-character pairing code, e.g. `K7QX2P`. Excludes visually
/// ambiguous characters (0/O, 1/I) since a person types this by hand.
String generatePairingCode() {
  final random = Random.secure();
  return List.generate(
    6,
    (_) => _codeAlphabet[random.nextInt(_codeAlphabet.length)],
  ).join();
}

const _identityKey = 'sync_group_identity';
const _tokenKey = 'sync_group_token';

/// Talks to a self-hosted PocketBase instance: pairing (create/join a
/// sync group) and the push/pull operations [SyncEngine] needs.
class PocketBaseSyncClient implements SyncBackend {
  PocketBaseSyncClient({required String baseUrl, required this.settings})
    : _pb = PocketBase(baseUrl);

  final PocketBase _pb;
  final AppSettingsRepository settings;

  /// Creates a new sync group with a fresh pairing code, authenticates
  /// as it, and returns the code for the user to share with other
  /// devices.
  Future<String> createGroup() async {
    final code = generatePairingCode();
    await _pb
        .collection('sync_groups')
        .create(
          body: {'username': code, 'password': code, 'passwordConfirm': code},
        );
    await _authenticate(code);
    return code;
  }

  /// Authenticates as the sync group identified by [code], entered by
  /// the user from another device.
  Future<void> joinGroup(String code) => _authenticate(code);

  Future<void> _authenticate(String code) async {
    final auth = await _pb
        .collection('sync_groups')
        .authWithPassword(code, code);
    await settings.setValue(_identityKey, code);
    await settings.setValue(_tokenKey, auth.token);
    _pb.authStore.save(auth.token, auth.record);
  }

  /// Restores a previously-saved auth session, if any, so the app
  /// doesn't need to re-pair on every restart. Returns whether a session
  /// was restored.
  Future<bool> restoreSession() async {
    final token = await settings.getValue(_tokenKey);
    if (token == null) return false;
    _pb.authStore.save(token, null);
    return _pb.authStore.isValid;
  }

  @override
  Future<void> upsert(String collection, Map<String, Object?> record) async {
    final entityId = record['id']! as String;
    final syncGroup = _pb.authStore.record?.id;
    if (syncGroup == null) return;

    final body = {
      'entity_id': entityId,
      'sync_group': syncGroup,
      'updated_at': record['updatedAt'],
      'deleted': record['deleted'] ?? false,
      'data': record,
    };

    final existing = await _pb
        .collection(collection)
        .getList(
          page: 1,
          perPage: 1,
          filter: 'entity_id = "$entityId"',
        );
    if (existing.items.isEmpty) {
      await _pb.collection(collection).create(body: body);
    } else {
      await _pb.collection(collection).update(existing.items.first.id, body: body);
    }
  }

  @override
  Future<List<Map<String, Object?>>> listChangedSince(
    String collection,
    DateTime cursor,
  ) async {
    final result = await _pb
        .collection(collection)
        .getList(
          page: 1,
          perPage: 200,
          filter: 'updated_at > "${cursor.toIso8601String()}"',
          sort: 'updated_at',
        );
    return [
      for (final item in result.items)
        {
          'entity_id': item.data['entity_id'],
          'updated_at': item.data['updated_at'],
          'deleted': item.data['deleted'],
          'data': item.data['data'],
        },
    ];
  }
}
```

Note for the executor: `perPage: 200` means a single sync pass won't see more than 200 changes per collection since the last cursor — acceptable for a personal-planner data volume in v1; paginating `listChangedSince` is future work if it ever matters.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/unit/pocketbase_sync_client_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/sync/pocketbase_sync_client.dart test/unit/pocketbase_sync_client_test.dart
git commit -m "feat: add PocketBaseSyncClient (pairing + push/pull backend)"
```

---

### Task 10: Pairing UI + sync triggers wired into the app

**Files:**
- Modify: `pubspec.yaml` (add `connectivity_plus`)
- Create: `lib/features/pairing/pairing_providers.dart`
- Create: `lib/features/pairing/widgets/pairing_screen.dart`
- Create: `lib/core/sync/sync_trigger.dart`
- Modify: `lib/router.dart` (add `/pairing` route)
- Modify: `lib/main.dart` (start sync triggers after the sembast overrides are wired up)
- Test: `test/widget/pairing_screen_test.dart`

**Interfaces:**
- Consumes: `PocketBaseSyncClient` (Task 9), `SyncEngine`/`syncCollections` (Task 8), `AppSettingsRepository` (existing provider).
- Produces: a `/pairing` screen with "Create group" (shows the generated code) and "Join group" (a text field + submit) actions; `startSyncTriggers({required SyncEngine engine, required Connectivity connectivity})` called once from `main.dart`, returns a `SyncTriggerHandle` with a `dispose()` for tests/teardown.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add connectivity_plus`
Expected: `pubspec.yaml` gains a `connectivity_plus: ^<resolved version>` line.

- [ ] **Step 2: Write the pairing providers**

```dart
// lib/features/pairing/pairing_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';

/// The PocketBase base URL. Overridden at the composition root
/// (`main.dart`) once a real deployment URL is known; defaults to the
/// local dev server started by `docker compose up pocketbase` (see
/// Task 1).
final pocketBaseBaseUrlProvider = Provider<String>(
  (ref) => 'http://localhost:8090',
);

final pocketBaseSyncClientProvider = Provider<PocketBaseSyncClient>((ref) {
  throw UnimplementedError(
    'Override with a PocketBaseSyncClient built from appSettingsRepositoryProvider '
    'at the composition root — see sembastOverrides in main.dart.',
  );
});

/// Whether this device currently belongs to a sync group (has a stored
/// pairing session), and the actions to create/join one.
class PairingNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.watch(pocketBaseSyncClientProvider).restoreSession();

  Future<String> createGroup() async {
    final code = await ref.read(pocketBaseSyncClientProvider).createGroup();
    state = const AsyncData(true);
    return code;
  }

  Future<void> joinGroup(String code) async {
    await ref.read(pocketBaseSyncClientProvider).joinGroup(code);
    state = const AsyncData(true);
  }
}

final pairingProvider = AsyncNotifierProvider<PairingNotifier, bool>(
  PairingNotifier.new,
);
```

- [ ] **Step 3: Write the pairing screen**

```dart
// lib/features/pairing/widgets/pairing_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/pairing/pairing_providers.dart';

/// Lets the user create a new sync group (and see the code to share
/// with their other devices) or join an existing one by entering a
/// code. See spec: "No accounts — pairing code as the auth mechanism."
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _codeController = TextEditingController();
  String? _createdCode;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    setState(() => _error = null);
    try {
      final code = await ref.read(pairingProvider.notifier).createGroup();
      setState(() => _createdCode = code);
    } catch (_) {
      setState(() => _error = 'Could not create a sync group. Try again.');
    }
  }

  Future<void> _joinGroup() async {
    setState(() => _error = null);
    try {
      await ref.read(pairingProvider.notifier).joinGroup(
        _codeController.text.trim().toUpperCase(),
      );
    } catch (_) {
      setState(() => _error = 'That code wasn\'t found. Check it and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync devices')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_createdCode != null) ...[
              Text('Your pairing code: $_createdCode'),
              const Text('Enter this on your other device to sync.'),
              const SizedBox(height: 24),
            ] else ...[
              ElevatedButton(
                onPressed: _createGroup,
                child: const Text('Create a new sync group'),
              ),
              const SizedBox(height: 24),
            ],
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Pairing code'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _joinGroup,
              child: const Text('Join with a code'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write the sync trigger wiring**

```dart
// lib/core/sync/sync_trigger.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

/// Handle returned by [startSyncTriggers], to stop triggering sync
/// (tests, or a future "sign out").
class SyncTriggerHandle {
  SyncTriggerHandle._(this._timer, this._connectivitySubscription);

  final Timer _timer;
  final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  void dispose() {
    _timer.cancel();
    _connectivitySubscription.cancel();
  }
}

/// Starts syncing [engine] against [syncCollections] on: right now (app
/// start), whenever connectivity is regained, and every 30 seconds while
/// the app is running. See spec: "Sync triggers: app start, connectivity
/// regained, and a foreground timer (~30s)."
SyncTriggerHandle startSyncTriggers({
  required SyncEngine engine,
  Connectivity? connectivity,
  Duration interval = const Duration(seconds: 30),
}) {
  final connectivityChecker = connectivity ?? Connectivity();

  unawaited(engine.syncAll(syncCollections));

  final timer = Timer.periodic(interval, (_) {
    unawaited(engine.syncAll(syncCollections));
  });

  final subscription = connectivityChecker.onConnectivityChanged.listen((
    results,
  ) {
    if (results.any((r) => r != ConnectivityResult.none)) {
      unawaited(engine.syncAll(syncCollections));
    }
  });

  return SyncTriggerHandle._(timer, subscription);
}
```

- [ ] **Step 5: Wire the pairing route into `router.dart`**

Read `lib/router.dart` first to match its existing `GoRoute` list style, then add:

```dart
GoRoute(
  path: '/pairing',
  builder: (context, state) => const PairingScreen(),
),
```

alongside the existing top-level routes, with the matching import (`import 'package:taskframe/features/pairing/widgets/pairing_screen.dart';`) added at the top of the file next to the other feature-screen imports.

- [ ] **Step 6: Wire providers and triggers into `main.dart`**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/app.dart';
import 'package:taskframe/core/platform/persistent_storage.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/storage/first_run_seed.dart';
import 'package:taskframe/core/storage/sembast_overrides.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_engine.dart';
import 'package:taskframe/core/sync/sync_trigger.dart';
import 'package:taskframe/features/pairing/pairing_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();
  await seedIfEmpty(db);
  await requestPersistentStorage();

  final appSettings = SembastAppSettingsRepository(db);
  final syncClient = PocketBaseSyncClient(
    baseUrl: 'http://localhost:8090',
    settings: appSettings,
  );
  final syncEngine = SyncEngine(db: db, settings: appSettings, backend: syncClient);
  startSyncTriggers(engine: syncEngine);

  runApp(
    ProviderScope(
      overrides: [
        ...sembastOverrides(db),
        pocketBaseSyncClientProvider.overrideWithValue(syncClient),
      ],
      child: const App(),
    ),
  );
}
```

- [ ] **Step 7: Write the widget test**

```dart
// test/widget/pairing_screen_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/features/pairing/pairing_providers.dart';
import 'package:taskframe/features/pairing/widgets/pairing_screen.dart';

void main() {
  testWidgets('shows create and join controls', (tester) async {
    final client = PocketBaseSyncClient(
      baseUrl: 'http://localhost:8090',
      settings: InMemoryAppSettingsRepository(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pocketBaseSyncClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: PairingScreen()),
      ),
    );

    expect(find.text('Create a new sync group'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
  });
}
```

- [ ] **Step 8: Run to verify it passes**

Run: `flutter test test/widget/pairing_screen_test.dart`
Expected: PASS

- [ ] **Step 9: Run the full suite**

Run: `make analyze test`
Expected: PASS — `flutter analyze`/`custom_lint` clean, all tests green.

- [ ] **Step 10: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/pairing lib/core/sync/sync_trigger.dart lib/router.dart lib/main.dart test/widget/pairing_screen_test.dart
git commit -m "feat: add pairing screen and wire sync triggers into the app"
```

---

### Task 11: Integration test against a real local PocketBase

**Files:**
- Create: `test/integration/pocketbase_sync_test.dart`
- Modify: `Makefile` (add an `integration-test` target documenting the PocketBase dependency)

**Interfaces:**
- Consumes: `PocketBaseSyncClient` (Task 9), `SyncEngine`/`syncCollections` (Task 8), a running PocketBase from Task 1 with collections already set up.
- Produces: none — this is the spec's required end-to-end coverage ("Integration tests running push/pull against a local PocketBase instance").

- [ ] **Step 1: Add the Makefile target**

```makefile
# Makefile — add near the other test targets
integration-test:
	@echo "Requires: docker compose up -d pocketbase, then"
	@echo "  dart run scripts/setup_pocketbase.dart http://localhost:8090 dev@taskframe.local dev-password-change-me"
	flutter test test/integration
```

Also add `integration-test` to the `.PHONY` line at the top of the file, alongside the existing targets.

- [ ] **Step 2: Write the integration test**

```dart
// test/integration/pocketbase_sync_test.dart
//
// Requires a local PocketBase with collections already set up — see
// `make integration-test`. Skipped by `make check`/`make test`, which
// only run test/unit and test/widget.
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

void main() {
  group('PocketBase sync (requires a local server)', () {
    late Database deviceADb;
    late Database deviceBDb;
    late AppSettingsRepository deviceASettings;
    late AppSettingsRepository deviceBSettings;
    late PocketBaseSyncClient deviceAClient;
    late PocketBaseSyncClient deviceBClient;
    late SyncEngine deviceAEngine;
    late SyncEngine deviceBEngine;
    const things = SyncCollection(name: 'tasks', store: null);

    setUp(() async {
      deviceADb = await newDatabaseFactoryMemory().openDatabase('a.db');
      deviceBDb = await newDatabaseFactoryMemory().openDatabase('b.db');
      deviceASettings = InMemoryAppSettingsRepository();
      deviceBSettings = InMemoryAppSettingsRepository();
      deviceAClient = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: deviceASettings,
      );
      deviceBClient = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: deviceBSettings,
      );
      deviceAEngine = SyncEngine(
        db: deviceADb,
        settings: deviceASettings,
        backend: deviceAClient,
      );
      deviceBEngine = SyncEngine(
        db: deviceBDb,
        settings: deviceBSettings,
        backend: deviceBClient,
      );
    });

    test('an edit on device A appears on device B after pairing', () async {
      final code = await deviceAClient.createGroup();
      await deviceBClient.joinGroup(code);

      await tasksStore.record('t1').put(deviceADb, {
        'id': 't1',
        'title': 'Buy milk',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });

      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      final onB = await tasksStore.record('t1').get(deviceBDb);
      expect(onB!['title'], 'Buy milk');
    });

    test('a delete on device A propagates to device B', () async {
      final code = await deviceAClient.createGroup();
      await deviceBClient.joinGroup(code);

      await tasksStore.record('t2').put(deviceADb, {
        'id': 't2',
        'title': 'Temp',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });
      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      await tasksStore.record('t2').put(deviceADb, {
        'id': 't2',
        'title': 'Temp',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': true,
      });
      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      final onB = await tasksStore.record('t2').get(deviceBDb);
      expect(onB!['deleted'], isTrue);
    });

    test('concurrent edits resolve to the newer updatedAt', () async {
      final code = await deviceAClient.createGroup();
      await deviceBClient.joinGroup(code);

      final base = DateTime.now().toUtc();
      await tasksStore.record('t3').put(deviceADb, {
        'id': 't3',
        'title': 'From A',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': base.toIso8601String(),
        'deleted': false,
      });
      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      await tasksStore.record('t3').put(deviceADb, {
        'id': 't3',
        'title': 'Older edit from A',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': base.add(const Duration(seconds: 1)).toIso8601String(),
        'deleted': false,
      });
      await tasksStore.record('t3').put(deviceBDb, {
        'id': 't3',
        'title': 'Newer edit from B',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': base.add(const Duration(seconds: 5)).toIso8601String(),
        'deleted': false,
      });

      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);
      await deviceAEngine.syncAll([_tasksCollection]);

      final onA = await tasksStore.record('t3').get(deviceADb);
      expect(onA!['title'], 'Newer edit from B');
    });
  });
}

const _tasksCollection = SyncCollection(name: 'tasks', store: tasksStore);
```

Note for the executor: replace the unused `things`/`const things = SyncCollection(name: 'tasks', store: null)` local left over from drafting with the module-level `_tasksCollection` constant already used throughout the tests — remove the dead `things` declaration from `setUp`'s enclosing scope before running.

- [ ] **Step 3: Bring up a clean PocketBase and run**

Run: `docker compose down -v && docker compose up -d pocketbase`
Run: `docker compose exec pocketbase /pb/pocketbase superuser upsert dev@taskframe.local dev-password-change-me`
Run: `dart run scripts/setup_pocketbase.dart http://localhost:8090 dev@taskframe.local dev-password-change-me`
Run: `make integration-test`
Expected: PASS (all three tests)

- [ ] **Step 4: Commit**

```bash
git add test/integration/pocketbase_sync_test.dart Makefile
git commit -m "test: add integration tests for push/pull against a local PocketBase"
```

---

## Self-Review Notes

- **Spec coverage:** self-hosted PocketBase (Task 1), no-login pairing (Tasks 1, 9, 10), flexible `data` JSON per collection (Task 1's collection shape + Task 8/9's raw-map sync), `updatedAt`/`deleted` on every synced model (Tasks 3–7), LWW `SyncEngine` (Task 8), sync triggers app-start/connectivity/timer (Task 10), error handling — silent retry, cursor-gated partial-failure resumption, pairing-error surfaced in UI (Tasks 8's `syncAll` try/catch, Task 10's `_error` state) — all covered. Integration coverage matches the spec's four required scenarios (Task 11), and unit coverage matches its five required LWW cases (Task 8).
- **Placeholder scan:** two scratch leftovers were caught and explicitly flagged for removal inline (Task 4's first draft test, Task 8's `store: null` local, Task 11's `things` local) rather than left as ambiguous TODOs — each has the exact replacement content next to it.
- **Type consistency:** `SyncCollection(name, store)`, `SyncBackend.upsert(String, Map<String,Object?>)`/`listChangedSince(String, DateTime)`, and the `sync_push_<name>`/`sync_pull_<name>` cursor key convention are used identically across Tasks 8, 9, 10, and 11.
