import 'package:sembast/sembast.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/data/sembast_day_blocks_repository.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/template/data/template_repository.dart';
import 'package:taskframe/features/template/models/template.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A [TemplateRepository] backed by a sembast [Database], persisting
/// templates across restarts. Records are keyed by [Template.id]; an
/// `order` field (set once at creation, preserved on rename) keeps
/// `load` in creation order.
class SembastTemplateRepository implements TemplateRepository {
  /// Creates a [SembastTemplateRepository] reading/writing [_db].
  new(this._db);

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
  /// Creates a [SembastTemplateBlocksRepository] reading/writing [_db].
  new(this._db);

  final Database _db;

  @override
  Future<List<TimeObject>> load(String templateId) async {
    final finder = Finder(
      filter: Filter.equals('templateId', templateId),
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
      title: title ?? 'title',
      start: start,
      end: end,
      kind: kind,
      locked: false,
      categoryId: categoryId ?? Category.defaultId,
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
    await templateBlocksStore.record(block.id).delete(_db);
  }

  @override
  Future<void> deleteAll(String templateId) async {
    final finder = Finder(filter: Filter.equals('templateId', templateId));
    await templateBlocksStore.delete(_db, finder: finder);
  }
}
