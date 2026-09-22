import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
import 'package:taskframe/features/day/widgets/schedule_columns_page.dart';
import 'package:taskframe/features/template/models/template.dart';
import 'package:taskframe/features/template/providers.dart';

/// How many template columns one page shows: one at narrow widths (swipe
/// or arrows page between templates one at a time), or up to seven at wide
/// widths — matching `DayScreen`'s week-view cap — with further templates
/// on additional pages reached the same way.
int _itemsPerPageFor(bool narrow) => narrow ? 1 : 7;

/// How many pages [slotCount] slots (templates plus the trailing
/// add-template slot) need at [itemsPerPage] per page.
int _pageCountFor(int slotCount, int itemsPerPage) =>
    slotCount == 0 ? 0 : (slotCount - 1) ~/ itemsPerPage + 1;

/// Duration a block created via the "Add block" button gets, before
/// [findNextFreeSlot] shrinks it to fit a shorter gap or the template's
/// end. Mirrors `DayScreen`'s own default.
const _newBlockDuration = Duration(minutes: 60);

/// The templates screen: a set of named templates, each with its own
/// full schedule editor reusing `DayGrid`, paged [_itemsPerPageFor] at a
/// time (swipe or arrows between pages) exactly like `DayScreen` pages
/// between days/weeks.
///
/// A synthetic slot always follows the last real template — a lone "+"
/// that creates a new template — so the templates list is never truly
/// empty on screen. The AppBar's own "+" instead adds a block to the
/// first template on the current page, mirroring `DayScreen`'s add
/// button.
class TemplatesScreen extends ConsumerStatefulWidget {
  /// Creates a [TemplatesScreen].
  const new({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  late final PageController _pageController;
  late final PageSwipeForwarder _swipeForwarder;

  /// The last [_itemsPerPageFor] value this screen was built at, used to
  /// detect a narrow/wide breakpoint crossing so [_pageIndex] can be
  /// converted to keep roughly the same template in view.
  int? _lastItemsPerPage;

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

  /// Jumps [_pageController] to [_pageIndex] once it's attached to a
  /// mounted `PageView`. A `PageController`'s own `initialPage` only takes
  /// effect the first time it attaches to a scroll view, so a `_pageIndex`
  /// change made elsewhere (add/delete a template, a breakpoint crossing)
  /// needs this to actually move it. Scheduled as a post-frame callback so
  /// it runs after whatever build just changed `_pageIndex`.
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
    final itemsPerPage = _itemsPerPageFor(isNarrow(context));
    // templates.length (the pre-add count) is the new template's index.
    setState(() => _pageIndex = templates.length ~/ itemsPerPage);
    _syncPageControllerSoon();
  }

  Future<void> _deleteTemplate(Template template) async {
    final templates = ref.read(templateListProvider).value ?? const [];
    await ref.read(templateListProvider.notifier).deleteTemplate(template);
    if (!mounted) return;
    final remainingSlots = templates.length; // -1 template, +1 add-slot
    final itemsPerPage = _itemsPerPageFor(isNarrow(context));
    final pageCount = _pageCountFor(remainingSlots, itemsPerPage);
    if (_pageIndex >= pageCount) {
      setState(() => _pageIndex = pageCount - 1);
    }
    _syncPageControllerSoon();
  }

  /// Creates a new block on [template], in its next free slot, and opens
  /// the edit modal for it — the AppBar add button's equivalent of
  /// double-tapping/long-pressing free grid space, mirroring
  /// `DayScreen._createViaButton`.
  Future<void> _addBlockToTemplate(Template template) async {
    final settings = ref.read(daySettingsProvider);
    final existingBlocks =
        ref.read(templateBlocksProvider(template.id)).value ?? [];
    final start = findNextFreeSlot(
      day: templateAnchorDate,
      existingBlocks: existingBlocks,
      settings: settings,
      duration: _newBlockDuration,
    );
    final end =
        dayEndFor(
          templateAnchorDate,
          settings,
        ).isBefore(start.add(_newBlockDuration))
        ? dayEndFor(templateAnchorDate, settings)
        : start.add(_newBlockDuration);

    final created = await ref
        .read(templateBlocksProvider(template.id).notifier)
        .addBlock(start: start, end: end, kind: BlockKind.anchor);
    if (!mounted) return;
    await showBlockEditModal(
      context: context,
      column: TemplateColumn(template.id),
      actions: templateScheduleBlockActions,
      block: created,
    );
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
    final itemsPerPage = _itemsPerPageFor(narrow);
    // Templates plus the trailing add-template slot.
    final slotCount = templates.length + 1;
    final pageCount = _pageCountFor(slotCount, itemsPerPage);
    final currentPage = _pageIndex.clamp(0, pageCount - 1);

    // Convert the page index across an itemsPerPage change (a narrow/wide
    // breakpoint crossing) so roughly the same template stays in view —
    // see _syncPageControllerSoon's docs.
    if (_lastItemsPerPage != null && _lastItemsPerPage != itemsPerPage) {
      final anchorTemplateIndex = _pageIndex * _lastItemsPerPage!;
      _pageIndex = anchorTemplateIndex ~/ itemsPerPage;
      _syncPageControllerSoon();
    }
    _lastItemsPerPage = itemsPerPage;

    // The AppBar's add button targets the first real template on the
    // current page — the same "start of the visible page" rule
    // `DayScreen` uses for its own add button (`selectedDateProvider`
    // tracks the page's start date). `null` (and the button disabled)
    // when the current page holds only the add-template slot.
    final firstTemplateIndexOnPage = currentPage * itemsPerPage;
    final firstTemplateOnPage = firstTemplateIndexOnPage < templates.length
        ? templates[firstTemplateIndexOnPage]
        : null;

    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox(),
        title: const Text('Templates'),
        actions: [
          IconButton(
            tooltip: 'Add block',
            icon: const Icon(Icons.add),
            onPressed: firstTemplateOnPage == null
                ? null
                : () => unawaited(_addBlockToTemplate(firstTemplateOnPage)),
          ),
        ],
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load: $error')),
        data: (_) {
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
                itemCount: pageCount,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                itemBuilder: (context, page) {
                  final start = page * itemsPerPage;
                  final end = (start + itemsPerPage).clamp(0, slotCount);
                  final columnCount = end - start;
                  return ScheduleColumnsPage(
                    columnCount: columnCount,
                    settings: settings,
                    headerBuilder: (context, i) {
                      final slotIndex = start + i;
                      Widget content;
                      if (slotIndex >= templates.length) {
                        content = const SizedBox.shrink();
                      } else {
                        final template = templates[slotIndex];
                        content = _ColumnHeader(
                          key: ValueKey(template.id),
                          template: template,
                          onDelete: () => unawaited(_deleteTemplate(template)),
                        );
                      }
                      // A single-column page centers its header across the
                      // full width, which would otherwise put the delete
                      // button right under the switch arrows.
                      return columnCount == 1
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: scheduleEdgeFadeWidth,
                              ),
                              child: content,
                            )
                          : content;
                    },
                    gridBuilder:
                        (context, i, slotHeight, {required showHourLabels}) {
                          final slotIndex = start + i;
                          if (slotIndex >= templates.length) {
                            final gridSlotCount =
                                (settings.dayEndHour - settings.dayStartHour) *
                                4;
                            return Expanded(
                              child: SizedBox(
                                height: gridSlotCount * slotHeight,
                                child: _AddTemplateSlot(
                                  onTap: () => unawaited(_addTemplate()),
                                ),
                              ),
                            );
                          }
                          final template = templates[slotIndex];
                          return Expanded(
                            child: _TemplateColumnGrid(
                              template: template,
                              settings: settings,
                              slotHeight: slotHeight,
                              showHourLabels: showHourLabels,
                              onSwipeStart: _swipeForwarder.onSwipeStart,
                              onSwipeUpdate: _swipeForwarder.onSwipeUpdate,
                              onSwipeEnd: _swipeForwarder.onSwipeEnd,
                              onSwipeCancel: _swipeForwarder.onSwipeCancel,
                            ),
                          );
                        },
                  );
                },
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
              if (pageCount > 1) ...[
                Positioned(
                  top: 0,
                  left: 8,
                  height: scheduleHeaderHeight,
                  child: IconButton(
                    tooltip: itemsPerPage > 1
                        ? 'Previous templates'
                        : 'Previous template',
                    icon: const Icon(Icons.chevron_left),
                    style: IconButton.styleFrom(
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    onPressed: currentPage > 0
                        ? () => unawaited(_animateTo(currentPage - 1))
                        : null,
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 8,
                  height: scheduleHeaderHeight,
                  child: IconButton(
                    tooltip: itemsPerPage > 1
                        ? 'Next templates'
                        : 'Next template',
                    icon: const Icon(Icons.chevron_right),
                    style: IconButton.styleFrom(
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    onPressed: currentPage < pageCount - 1
                        ? () => unawaited(_animateTo(currentPage + 1))
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

/// The trailing "add a template" slot rendered in place of the last
/// column's grid content — a large tappable "+" filling the column, with
/// no header content above it (see [TemplatesScreen]'s `headerBuilder`).
class _AddTemplateSlot extends StatelessWidget {
  const new({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconButton(
        tooltip: 'Add template',
        iconSize: 40,
        icon: const Icon(Icons.add),
        onPressed: onTap,
      ),
    );
  }
}

class _ColumnHeader extends ConsumerStatefulWidget {
  const new({required this.template, required this.onDelete, super.key});

  final Template template;
  final VoidCallback onDelete;

  @override
  ConsumerState<_ColumnHeader> createState() => _ColumnHeaderState();
}

class _ColumnHeaderState extends ConsumerState<_ColumnHeader> {
  /// How long to wait after the last keystroke before autosaving the
  /// name, so a rename doesn't persist on every keystroke.
  static const _autosaveDelay = Duration(milliseconds: 500);

  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;
  late String _lastSaved;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.template.name);
    _lastSaved = widget.template.name;
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_ColumnHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Skip while focused: an external name change while the user is still
    // editing would otherwise be our own debounced save echoing back and
    // clobbering whatever they've typed since.
    if (oldWidget.template.name != widget.template.name &&
        !_focusNode.hasFocus) {
      _controller.text = widget.template.name;
      _lastSaved = widget.template.name;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _save();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(_autosaveDelay, _save);
  }

  void _save() {
    _debounce?.cancel();
    _debounce = null;
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty || trimmed == _lastSaved) return;
    _lastSaved = trimmed;
    unawaited(
      ref
          .read(templateListProvider.notifier)
          .renameTemplate(widget.template, name: trimmed),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: (_) => _scheduleSave(),
            onSubmitted: (_) => _save(),
          ),
        ),
        IconButton(
          tooltip: 'Delete template',
          icon: const Icon(Icons.delete_outline),
          visualDensity: VisualDensity.compact,
          onPressed: widget.onDelete,
        ),
      ],
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
