import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
import 'package:taskframe/features/day/widgets/schedule_block_actions.dart';
import 'package:taskframe/features/template/data/template_repository.dart';
import 'package:taskframe/features/template/models/template.dart';

/// The backing store for templates. Overriding this single provider is
/// enough to change where templates are loaded from and saved to.
final templateRepositoryProvider = Provider<TemplateRepository>(
  (ref) => InMemoryTemplateRepository(),
);

/// Holds the list of templates, loaded from [templateRepositoryProvider],
/// and lets consumers add/rename/delete them.
class TemplateListNotifier extends AsyncNotifier<List<Template>> {
  @override
  Future<List<Template>> build() => ref.watch(templateRepositoryProvider).load();

  /// Creates a new template named [name], adds it to the current state,
  /// and returns it.
  Future<Template> addTemplate({required String name}) async {
    final repository = ref.read(templateRepositoryProvider);
    final added = await repository.add(name: name);
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Renames [template] to [name], persisting via the repository and
  /// refreshing state.
  Future<void> renameTemplate(Template template, {required String name}) async {
    final repository = ref.read(templateRepositoryProvider);
    final renamed = await repository.rename(template, name: name);
    state = AsyncData([
      for (final t in state.value ?? <Template>[])
        if (t.id == template.id) renamed else t,
    ]);
  }

  /// Removes [template], persisting via the repository and refreshing
  /// state.
  Future<void> deleteTemplate(Template template) async {
    final repository = ref.read(templateRepositoryProvider);
    await repository.delete(template);
    state = AsyncData([
      for (final t in state.value ?? <Template>[])
        if (t.id != template.id) t,
    ]);
  }
}

/// The list of templates.
final templateListProvider =
    AsyncNotifierProvider<TemplateListNotifier, List<Template>>(
      TemplateListNotifier.new,
    );

/// The backing store for template blocks.
final templateBlocksRepositoryProvider = Provider<TemplateBlocksRepository>(
  (ref) => InMemoryTemplateBlocksRepository(),
);

/// Holds the timeline blocks for one template, loaded from
/// [templateBlocksRepositoryProvider], and lets a `TemplatesScreen` add
/// new ones — mirrors `DayBlocksNotifier`, minus `copyToNextDay`, which
/// has no template equivalent.
class TemplateBlocksNotifier extends AsyncNotifier<List<TimeObject>> {
  TemplateBlocksNotifier(this.templateId);

  /// The template these blocks belong to.
  final String templateId;

  @override
  Future<List<TimeObject>> build() =>
      ref.watch(templateBlocksRepositoryProvider).load(templateId);

  Future<TimeObject> addBlock({
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  }) async {
    final repository = ref.read(templateBlocksRepositoryProvider);
    final added = await repository.add(
      templateId,
      start: start,
      end: end,
      kind: kind,
      title: title,
      categoryId: categoryId,
    );
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Updates [block]'s title/start/end/kind, persisting via the
  /// repository and refreshing state. Silently does nothing if the
  /// resulting start/end would be invalid (see [isValidBlockEdit]).
  Future<void> updateBlock(
    TimeObject block, {
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  }) async {
    final newStart = start ?? block.start;
    final newEnd = end ?? block.end;
    final others = (state.value ?? []).where((b) => b.id != block.id).toList();
    final settings = ref.read(daySettingsProvider);
    if (!isValidBlockEdit(
      start: newStart,
      end: newEnd,
      settings: settings,
      day: templateAnchorDate,
      others: others,
    )) {
      return;
    }

    final repository = ref.read(templateBlocksRepositoryProvider);
    final updated = await repository.update(
      block,
      templateId: templateId,
      title: title,
      start: start,
      end: end,
      kind: kind,
      categoryId: categoryId,
    );
    state = AsyncData([
      for (final b in state.value ?? <TimeObject>[])
        if (b.id == block.id) updated else b,
    ]);
  }

  Future<void> deleteBlock(TimeObject block) async {
    final repository = ref.read(templateBlocksRepositoryProvider);
    await repository.delete(block, templateId: templateId);
    state = AsyncData([
      for (final b in state.value ?? <TimeObject>[])
        if (b.id != block.id) b,
    ]);
  }
}

/// The timeline blocks for a given template.
final templateBlocksProvider =
    AsyncNotifierProvider.family<TemplateBlocksNotifier, List<TimeObject>, String>(
      TemplateBlocksNotifier.new,
    );

/// A [ScheduleController] backed by [templateBlocksProvider]/
/// [templateBlocksRepositoryProvider]. Every [ScheduleColumn] it's given
/// must be a [TemplateColumn].
class TemplateScheduleController extends ScheduleController {
  const TemplateScheduleController();

  String _idOf(ScheduleColumn column) => (column as TemplateColumn).templateId;

  @override
  List<TimeObject>? blocksOf(Ref ref, ScheduleColumn column) =>
      ref.read(templateBlocksProvider(_idOf(column))).value;

  @override
  Future<void> moveBlock(
    Ref ref, {
    required TimeObject block,
    required ScheduleColumn fromColumn,
    required ScheduleColumn toColumn,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    final fromId = _idOf(fromColumn);
    final toId = _idOf(toColumn);
    final repository = ref.read(templateBlocksRepositoryProvider);
    await repository.move(
      block,
      fromTemplateId: fromId,
      toTemplateId: toId,
      newStart: newStart,
      newEnd: newEnd,
    );
    ref.invalidate(templateBlocksProvider(fromId));
    ref.invalidate(templateBlocksProvider(toId));
    await ref.read(templateBlocksProvider(fromId).future);
    await ref.read(templateBlocksProvider(toId).future);
  }
}

String _idOfColumn(ScheduleColumn column) => (column as TemplateColumn).templateId;

List<TimeObject>? _watchTemplateBlocks(WidgetRef ref, ScheduleColumn column) =>
    ref.watch(templateBlocksProvider(_idOfColumn(column))).value;

Future<void> _updateTemplateBlock(
  WidgetRef ref,
  ScheduleColumn column,
  TimeObject block, {
  String? title,
  DateTime? start,
  DateTime? end,
  BlockKind? kind,
  String? categoryId,
}) => ref
    .read(templateBlocksProvider(_idOfColumn(column)).notifier)
    .updateBlock(
      block,
      title: title,
      start: start,
      end: end,
      kind: kind,
      categoryId: categoryId,
    );

Future<void> _deleteTemplateBlock(
  WidgetRef ref,
  ScheduleColumn column,
  TimeObject block,
) => ref.read(templateBlocksProvider(_idOfColumn(column)).notifier).deleteBlock(block);

/// The [ScheduleBlockActions] `BlockEditModal` uses when editing a
/// template block. Every [ScheduleColumn] passed to it must be a
/// [TemplateColumn].
const templateScheduleBlockActions = ScheduleBlockActions(
  watchBlocks: _watchTemplateBlocks,
  updateBlock: _updateTemplateBlock,
  deleteBlock: _deleteTemplateBlock,
);
