import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
import 'package:taskframe/features/day/widgets/schedule_columns_page.dart';
import 'package:taskframe/features/template/models/template.dart';
import 'package:taskframe/features/template/providers.dart';

/// The templates screen: a set of named templates, each with its own
/// full schedule editor reusing `DayGrid`. Narrow widths show one
/// template per page (swipe or arrows between templates); wide widths
/// show every template as a side-by-side column.
class TemplatesScreen extends ConsumerStatefulWidget {
  /// Creates a [TemplatesScreen].
  const new({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  /// Only actually attached to a `PageView` at narrow widths — see
  /// [_syncPageControllerSoon].
  late final PageController _pageController;
  late final PageSwipeForwarder _swipeForwarder;

  /// The last width class this screen was built at, used to detect a
  /// narrow/wide breakpoint crossing.
  bool? _wasNarrow;

  int _pageIndex = 0;

  /// The next default name's number. Only ever increases, so deleting
  /// "Template 1" and adding again yields "Template 3" rather than a
  /// second "Template 2" — a count-based name collides after any delete.
  int _nextTemplateNumber = 1;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _swipeForwarder = PageSwipeForwarder(_pageController);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Jumps [_pageController] to [_pageIndex] once it's actually attached
  /// to a mounted `PageView` (i.e. once the screen is narrow).
  ///
  /// A `PageController`'s own `initialPage` only takes effect the first
  /// time it attaches to a scroll view — since this screen only mounts a
  /// `PageView` at narrow widths, a `_pageIndex` change made while wide
  /// (add/delete a template) would otherwise be silently lost the next
  /// time the viewport narrows and the `PageView` attaches for the first
  /// time. Scheduled as a post-frame callback so it runs after whatever
  /// build just attached (or re-attached) the controller.
  void _syncPageControllerSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(_pageIndex);
    });
  }

  Future<void> _addTemplate() async {
    final templates = ref.read(templateListProvider).value ?? const [];
    final name = 'Template ${_nextTemplateNumber++}';
    await ref.read(templateListProvider.notifier).addTemplate(name: name);
    if (!mounted) return;
    setState(() => _pageIndex = templates.length);
    _syncPageControllerSoon();
  }

  Future<void> _deleteTemplate(Template template) async {
    final templates = ref.read(templateListProvider).value ?? const [];
    await ref.read(templateListProvider.notifier).deleteTemplate(template);
    if (!mounted) return;
    final remaining = templates.length - 1;
    if (_pageIndex >= remaining && remaining > 0) {
      setState(() => _pageIndex = remaining - 1);
    } else if (remaining == 0) {
      setState(() => _pageIndex = 0);
    }
    _syncPageControllerSoon();
  }

  Future<void> _animateTo(int index) => _pageController.animateToPage(
    index,
    duration: schedulePageAnimationDuration,
    curve: schedulePageAnimationCurve,
  );

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templateListProvider);
    final templates = templatesAsync.value ?? const <Template>[];
    final narrow = isNarrow(context);
    final settings = ref.watch(daySettingsProvider);
    final currentIndex = templates.isEmpty
        ? 0
        : _pageIndex.clamp(0, templates.length - 1);

    // Only matters the moment the viewport *becomes* narrow — see
    // _syncPageControllerSoon's docs.
    if (_wasNarrow != null && _wasNarrow != narrow && narrow) {
      _syncPageControllerSoon();
    }
    _wasNarrow = narrow;

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

          if (!narrow) {
            return ScheduleColumnsPage(
              columnCount: templates.length,
              settings: settings,
              headerBuilder: (context, i) => _ColumnHeader(
                key: ValueKey(templates[i].id),
                template: templates[i],
                onDelete: () => unawaited(_deleteTemplate(templates[i])),
              ),
              gridBuilder: (context, i, slotHeight, showHourLabels) => Expanded(
                child: _TemplateColumnGrid(
                  template: templates[i],
                  settings: settings,
                  slotHeight: slotHeight,
                  showHourLabels: showHourLabels,
                ),
              ),
            );
          }

          return Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                // Same trick DayScreen uses: PageView's own recognizer
                // never competes for drags that start on a block, while
                // PageScrollPhysics' snap-to-page ballistic simulation
                // still applies to drags forwarded via _swipeForwarder.
                physics: const NeverScrollableScrollPhysics(
                  parent: PageScrollPhysics(),
                ),
                itemCount: templates.length,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                itemBuilder: (context, i) => ScheduleColumnsPage(
                  columnCount: 1,
                  settings: settings,
                  headerBuilder: (context, _) => _ColumnHeader(
                    key: ValueKey(templates[i].id),
                    template: templates[i],
                    onDelete: () => unawaited(_deleteTemplate(templates[i])),
                  ),
                  gridBuilder: (context, _, slotHeight, showHourLabels) =>
                      Expanded(
                        child: _TemplateColumnGrid(
                          template: templates[i],
                          settings: settings,
                          slotHeight: slotHeight,
                          showHourLabels: showHourLabels,
                          onSwipeStart: _swipeForwarder.onSwipeStart,
                          onSwipeUpdate: _swipeForwarder.onSwipeUpdate,
                          onSwipeEnd: _swipeForwarder.onSwipeEnd,
                          onSwipeCancel: _swipeForwarder.onSwipeCancel,
                        ),
                      ),
                ),
              ),
              // Fades the sliding header content to the background color
              // before it reaches either arrow, matching DayScreen.
              const Positioned(
                top: 0,
                left: 0,
                width: scheduleEdgeFadeWidth,
                height: scheduleHeaderHeight,
                child: IgnorePointer(child: ScheduleEdgeFade(alignLeft: true)),
              ),
              const Positioned(
                top: 0,
                right: 0,
                width: scheduleEdgeFadeWidth,
                height: scheduleHeaderHeight,
                child: IgnorePointer(child: ScheduleEdgeFade(alignLeft: false)),
              ),
              if (templates.length > 1) ...[
                Positioned(
                  top: 0,
                  left: 8,
                  height: scheduleHeaderHeight,
                  child: IconButton(
                    tooltip: 'Previous template',
                    icon: const Icon(Icons.chevron_left),
                    style: IconButton.styleFrom(
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    onPressed: currentIndex > 0
                        ? () => unawaited(_animateTo(currentIndex - 1))
                        : null,
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 8,
                  height: scheduleHeaderHeight,
                  child: IconButton(
                    tooltip: 'Next template',
                    icon: const Icon(Icons.chevron_right),
                    style: IconButton.styleFrom(
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    onPressed: currentIndex < templates.length - 1
                        ? () => unawaited(_animateTo(currentIndex + 1))
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
  const new({required this.template, required this.onDelete, super.key});

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
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
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
  const new({
    required this.template,
    required this.settings,
    required this.slotHeight,
    required this.showHourLabels,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
    this.onSwipeCancel,
  });

  final Template template;
  final DaySettings settings;
  final double slotHeight;
  final bool showHourLabels;
  final GestureDragStartCallback? onSwipeStart;
  final GestureDragUpdateCallback? onSwipeUpdate;
  final GestureDragEndCallback? onSwipeEnd;
  final VoidCallback? onSwipeCancel;

  Future<void> _createAndOpen(
    BuildContext context,
    WidgetRef ref, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
  }) async {
    final created = await ref
        .read(templateBlocksProvider(template.id).notifier)
        .addBlock(start: start, end: end, kind: kind);
    if (!context.mounted) return;
    await showBlockEditModal(
      context: context,
      column: TemplateColumn(template.id),
      actions: templateScheduleBlockActions,
      block: created,
    );
  }

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
        showHourLabels: showHourLabels,
        onSwipeStart: onSwipeStart,
        onSwipeUpdate: onSwipeUpdate,
        onSwipeEnd: onSwipeEnd,
        onSwipeCancel: onSwipeCancel,
        onCreateBlock: ({required start, required end, required kind}) {
          unawaited(
            _createAndOpen(context, ref, start: start, end: end, kind: kind),
          );
        },
      ),
    );
  }
}
