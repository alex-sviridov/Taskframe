import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/template/models/template.dart';

/// Loads and stores the list of templates.
abstract class TemplateRepository {
  /// Returns every template, in creation order.
  Future<List<Template>> load();

  /// Creates a new template named [name] and returns it.
  Future<Template> add({required String name});

  /// Renames [template] to [name] and returns the updated template.
  Future<Template> rename(Template template, {required String name});

  /// Removes [template].
  Future<void> delete(Template template);
}

/// A [TemplateRepository] that keeps templates in memory for the life of
/// the app, starting empty.
class InMemoryTemplateRepository implements TemplateRepository {
  final List<Template> _templates = [];
  int _nextId = 0;

  @override
  Future<List<Template>> load() async => List.unmodifiable(_templates);

  @override
  Future<Template> add({required String name}) async {
    final template = Template(id: 'template-${_nextId++}', name: name);
    _templates.add(template);
    return template;
  }

  @override
  Future<Template> rename(Template template, {required String name}) async {
    final renamed = template.copyWith(name: name);
    final index = _templates.indexWhere((t) => t.id == template.id);
    if (index == -1) {
      throw StateError('Template ${template.id} not found');
    }
    _templates[index] = renamed;
    return renamed;
  }

  @override
  Future<void> delete(Template template) async {
    _templates.removeWhere((t) => t.id == template.id);
  }
}

/// Loads and stores the timeline blocks for a given template, mirroring
/// `DayBlocksRepository`'s shape but keyed by `templateId` instead of a
/// calendar date, with no seed data and no day-only "copy to next day"
/// equivalent.
abstract class TemplateBlocksRepository {
  /// Returns the blocks for [templateId].
  Future<List<TimeObject>> load(String templateId);

  /// Creates a new block on [templateId] and returns it. [title] defaults
  /// to a placeholder when omitted.
  Future<TimeObject> add(
    String templateId, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  });

  /// Moves [block] from [fromTemplateId] to [toTemplateId], updating its
  /// start/end to [newStart]/[newEnd], and returns the updated block.
  /// [fromTemplateId] and [toTemplateId] may be the same id.
  Future<TimeObject> move(
    TimeObject block, {
    required String fromTemplateId,
    required String toTemplateId,
    required DateTime newStart,
    required DateTime newEnd,
  });

  /// Updates [block] (which belongs to [templateId]) in place, replacing
  /// any of [title]/[start]/[end]/[kind]/[categoryId] that are given.
  /// Returns the updated block.
  Future<TimeObject> update(
    TimeObject block, {
    required String templateId,
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  });

  /// Removes [block] (which belongs to [templateId]).
  Future<void> delete(TimeObject block, {required String templateId});

  /// Removes every block belonging to [templateId], so deleting a
  /// template doesn't leave its blocks stranded in the store forever.
  Future<void> deleteAll(String templateId);
}

/// A [TemplateBlocksRepository] that keeps blocks in memory for the life
/// of the app, starting empty for every template.
class InMemoryTemplateBlocksRepository implements TemplateBlocksRepository {
  final Map<String, List<TimeObject>> _blocks = {};
  int _nextId = 0;

  @override
  Future<List<TimeObject>> load(String templateId) async => [
    ...?_blocks[templateId],
  ];

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
      id: 'template-block-${_nextId++}',
      title: title ?? 'title',
      start: start,
      end: end,
      kind: kind,
      locked: false,
      categoryId: categoryId ?? Category.defaultId,
    );
    _blocks[templateId] = [...?_blocks[templateId], block];
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
    final fromList = _blocks[fromTemplateId];
    if (fromList != null) {
      _blocks[fromTemplateId] = fromList
          .where((b) => b.id != block.id)
          .toList();
    }

    final moved = TimeObject(
      id: block.id,
      title: block.title,
      start: newStart,
      end: newEnd,
      kind: block.kind,
      locked: block.locked,
      categoryId: block.categoryId,
    );
    _blocks[toTemplateId] = [...?_blocks[toTemplateId], moved];
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
    final list = _blocks[templateId] ?? [];
    _blocks[templateId] = [
      for (final b in list)
        if (b.id == block.id) updated else b,
    ];
    return updated;
  }

  @override
  Future<void> delete(TimeObject block, {required String templateId}) async {
    final list = _blocks[templateId];
    if (list != null) {
      _blocks[templateId] = list.where((b) => b.id != block.id).toList();
    }
  }

  @override
  Future<void> deleteAll(String templateId) async {
    _blocks.remove(templateId);
  }
}
