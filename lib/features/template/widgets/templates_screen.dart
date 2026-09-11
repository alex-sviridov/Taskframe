import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/day_grid_sizing.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
import 'package:taskframe/features/day/widgets/hour_gutter.dart';
import 'package:taskframe/features/template/models/template.dart';
import 'package:taskframe/features/template/providers.dart';

const _minSlotHeight = 8.0;
const _headerHeight = 56.0;
const _columnGap = 8.0;
const _newBlockDuration = Duration(minutes: 60);

/// The templates screen: a set of named templates, each with its own
/// full schedule editor reusing `DayGrid`. Narrow widths show one
/// template per page (swipe/arrows between templates); wide widths show
/// every template as a side-by-side column.
class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  int _pageIndex = 0;

  Future<void> _addTemplate() async {
    final templates = ref.read(templateListProvider).value ?? const [];
    final name = 'Template ${templates.length + 1}';
    await ref.read(templateListProvider.notifier).addTemplate(name: name);
    setState(() => _pageIndex = templates.length);
  }

  Future<void> _deleteTemplate(Template template) async {
    final templates = ref.read(templateListProvider).value ?? const [];
    await ref.read(templateListProvider.notifier).deleteTemplate(template);
    final remaining = templates.length - 1;
    if (_pageIndex >= remaining && remaining > 0) {
      setState(() => _pageIndex = remaining - 1);
    } else if (remaining == 0) {
      setState(() => _pageIndex = 0);
    }
  }

  Future<void> _createViaButton(BuildContext context, Template template) async {
    final settings = ref.read(daySettingsProvider);
    final existingBlocks = ref.read(templateBlocksProvider(template.id)).value ?? [];
    final start = findNextFreeSlot(
      day: templateAnchorDate,
      existingBlocks: existingBlocks,
      settings: settings,
      duration: _newBlockDuration,
    );
    final end = dayEndFor(templateAnchorDate, settings).isBefore(start.add(_newBlockDuration))
        ? dayEndFor(templateAnchorDate, settings)
        : start.add(_newBlockDuration);

    final created = await ref
        .read(templateBlocksProvider(template.id).notifier)
        .addBlock(start: start, end: end, kind: BlockKind.anchor);
    if (!context.mounted) return;
    await showBlockEditModal(
      context: context,
      column: TemplateColumn(template.id),
      actions: templateScheduleBlockActions,
      block: created,
    );
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templateListProvider);
    final templates = templatesAsync.value ?? const <Template>[];
    final narrow = isNarrow(context);
    final currentIndex = templates.isEmpty
        ? 0
        : _pageIndex.clamp(0, templates.length - 1);

    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox(),
        title: const Text('Templates'),
        actions: [
          IconButton(
            tooltip: 'Add template',
            icon: const Icon(Icons.add),
            onPressed: () => unawaited(_addTemplate()),
          ),
        ],
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load: $error')),
        data: (_) {
          if (templates.isEmpty) {
            return const Center(child: Text('No templates yet'));
          }
          final visible = narrow ? [templates[currentIndex]] : templates;
          return Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    SizedBox(
                      height: _headerHeight,
                      child: Row(
                        children: [
                          const SizedBox(width: HourGutter.width),
                          for (var i = 0; i < visible.length; i++) ...[
                            if (i > 0)
                              const VerticalDivider(width: _columnGap, thickness: 1),
                            Expanded(child: _ColumnHeader(
                              template: visible[i],
                              onDelete: () => unawaited(_deleteTemplate(visible[i])),
                            )),
                          ],
                          const SizedBox(width: HourGutter.width),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final settings = ref.watch(daySettingsProvider);
                          final slotCount =
                              (settings.dayEndHour - settings.dayStartHour) * 4;
                          final slotHeight = resolveSlotHeight(
                            availableHeight: constraints.maxHeight,
                            slotCount: slotCount,
                            minSlotHeight: _minSlotHeight,
                          );
                          return SingleChildScrollView(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                HourGutter(settings: settings, slotHeight: slotHeight),
                                for (var i = 0; i < visible.length; i++) ...[
                                  if (i > 0) const SizedBox(width: _columnGap),
                                  Expanded(
                                    child: _TemplateColumnGrid(
                                      template: visible[i],
                                      settings: settings,
                                      slotHeight: slotHeight,
                                      onCreateViaButton: () =>
                                          unawaited(_createViaButton(context, visible[i])),
                                    ),
                                  ),
                                ],
                                HourGutter(settings: settings, slotHeight: slotHeight),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (narrow && templates.length > 1) ...[
                Positioned(
                  top: 0,
                  left: 8,
                  height: _headerHeight,
                  child: IconButton(
                    tooltip: 'Previous template',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: currentIndex > 0
                        ? () => setState(() => _pageIndex = currentIndex - 1)
                        : null,
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 8,
                  height: _headerHeight,
                  child: IconButton(
                    tooltip: 'Next template',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: currentIndex < templates.length - 1
                        ? () => setState(() => _pageIndex = currentIndex + 1)
                        : null,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ColumnHeader extends StatefulWidget {
  const _ColumnHeader({required this.template, required this.onDelete});

  final Template template;
  final VoidCallback onDelete;

  @override
  State<_ColumnHeader> createState() => _ColumnHeaderState();
}

class _ColumnHeaderState extends State<_ColumnHeader> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.template.name);
  }

  @override
  void didUpdateWidget(_ColumnHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template.name != widget.template.name) {
      _controller.text = widget.template.name;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isNotEmpty && trimmed != widget.template.name) {
                  unawaited(
                    ref
                        .read(templateListProvider.notifier)
                        .renameTemplate(widget.template, name: trimmed),
                  );
                }
              },
            ),
          ),
          IconButton(
            tooltip: 'Delete template',
            icon: const Icon(Icons.delete_outline),
            visualDensity: VisualDensity.compact,
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

class _TemplateColumnGrid extends ConsumerWidget {
  const _TemplateColumnGrid({
    required this.template,
    required this.settings,
    required this.slotHeight,
    required this.onCreateViaButton,
  });

  final Template template;
  final DaySettings settings;
  final double slotHeight;
  final VoidCallback onCreateViaButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocksAsync = ref.watch(templateBlocksProvider(template.id));
    return blocksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Failed to load: $error')),
      data: (blocks) => DayGrid(
        key: scheduleGridKeyFor(TemplateColumn(template.id)),
        date: templateAnchorDate,
        column: TemplateColumn(template.id),
        controller: const TemplateScheduleController(),
        actions: templateScheduleBlockActions,
        blocks: blocks,
        settings: settings,
        slotHeight: slotHeight,
        showHourLabels: false,
        onCreateBlock: ({required start, required end, required kind}) {
          unawaited(
            ref
                .read(templateBlocksProvider(template.id).notifier)
                .addBlock(start: start, end: end, kind: kind)
                .then((created) => showBlockEditModal(
                      context: context,
                      column: TemplateColumn(template.id),
                      actions: templateScheduleBlockActions,
                      block: created,
                    )),
          );
        },
      ),
    );
  }
}
