import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/date_format.dart';
import 'package:taskframe/features/day/day_blocks_provider.dart';
import 'package:taskframe/features/day/day_date_provider.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_schedule_block_actions.dart';
import 'package:taskframe/features/day/day_schedule_controller.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/drag_state_provider.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/template_apply_effects.dart';
import 'package:taskframe/features/day/week_utils.dart';
import 'package:taskframe/features/day/widgets/apply_template_button.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
import 'package:taskframe/features/day/widgets/schedule_columns_page.dart';

/// Half the page-index range paged over by [_DayScreenState._pageController],
/// centered on the date shown when the screen first builds. Gives roughly
/// 270 years of swiping in either direction.
const _pageSpread = 100000;

/// How long the drag pointer must stay in an edge zone before it pages to
/// the adjacent day/week.
const _edgeDwellDuration = Duration(milliseconds: 600);

/// Duration a block created via the add button gets, before
/// [findNextFreeSlot] shrinks it to fit a shorter gap or the day end.
const _newBlockDuration = Duration(minutes: 60);

/// Viewport width at/above which the schedule shows a full week (7 days)
/// per page instead of a single day.
const _weekBreakpoint = 900.0;

int _daysPerPageFor(double width) => width >= _weekBreakpoint ? 7 : 1;

/// The schedule screen: a date header above a 15-minute grid of the day's
/// (or week's) blocks, paged with a finger-tracked slide animation.
///
/// Below [_weekBreakpoint] it shows one day per page; at or above it, a
/// full week per page.
class DayScreen extends ConsumerStatefulWidget {
  /// Creates a [DayScreen].
  const new({super.key});

  @override
  ConsumerState<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends ConsumerState<DayScreen> {
  late PageController _pageController;
  late DateTime _anchorDate;
  int? _daysPerPage;
  Drag? _drag;
  bool _resyncScheduled = false;
  Timer? _edgeDwellTimer;
  int? _edgeDwellDirection;

  @override
  void initState() {
    super.initState();
    _anchorDate = ref.read(selectedDateProvider);
    _pageController = PageController(initialPage: _pageSpread);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_daysPerPage != null) return;

    _daysPerPage = _daysPerPageFor(MediaQuery.sizeOf(context).width);
    if (_daysPerPage == 7) {
      _anchorDate = startOfWeek(
        _anchorDate,
        firstDayOfWeek: ref.read(daySettingsProvider).firstDayOfWeek,
      );
    }
  }

  @override
  void dispose() {
    _cancelEdgeDwell();
    _pageController.dispose();
    super.dispose();
  }

  /// Creates a new block on the currently selected date, in its next free
  /// slot, and opens the edit modal for it — the AppBar add button's
  /// equivalent of double-tapping/long-pressing free grid space, without
  /// needing a tap location to infer a time from.
  Future<void> _createViaButton(BuildContext context) async {
    final date = ref.read(selectedDateProvider);
    final settings = ref.read(daySettingsProvider);
    final existingBlocks = ref.read(dayBlocksProvider(date)).value ?? [];
    final start = findNextFreeSlot(
      day: date,
      existingBlocks: existingBlocks,
      settings: settings,
      duration: _newBlockDuration,
    );
    final end = dayEndFor(date, settings).isBefore(start.add(_newBlockDuration))
        ? dayEndFor(date, settings)
        : start.add(_newBlockDuration);

    final created = await ref
        .read(dayBlocksProvider(date).notifier)
        .addBlock(start: start, end: end, kind: BlockKind.anchor);
    if (!context.mounted) return;
    await showBlockEditModal(
      context: context,
      column: DayColumn(date),
      actions: dayScheduleBlockActions,
      block: created,
    );
  }

  DateTime _startDateForPage(int page) => DateTime(
    _anchorDate.year,
    _anchorDate.month,
    _anchorDate.day + (page - _pageSpread) * _daysPerPage!,
  );

  void _onPageChanged(int page) {
    ref.read(selectedDateProvider.notifier).date = _startDateForPage(page);
  }

  Future<void> _animateBy(int units) async {
    final page = (_pageController.page ?? _pageController.initialPage).round();
    await _pageController.animateToPage(
      page + units,
      duration: schedulePageAnimationDuration,
      curve: schedulePageAnimationCurve,
    );
  }

  void _onSwipeStart(DragStartDetails details) {
    _drag = _pageController.position.drag(details, () => _drag = null);
  }

  void _onSwipeUpdate(DragUpdateDetails details) => _drag?.update(details);

  void _onSwipeEnd(DragEndDetails details) {
    _drag?.end(details);
    _drag = null;
  }

  void _onSwipeCancel() {
    _drag?.cancel();
    _drag = null;
  }

  void _handleDragPointer(DragState? drag) {
    if (drag == null) {
      _cancelEdgeDwell();
      return;
    }

    final box = context.findRenderObject()! as RenderBox;
    final localWidth = box.size.width;
    final localDx = box.globalToLocal(drag.pointerGlobalPosition).dx;
    int? direction;
    if (localDx <= scheduleEdgeFadeWidth) {
      direction = -1;
    } else if (localDx >= localWidth - scheduleEdgeFadeWidth) {
      direction = 1;
    }

    if (direction == null) {
      _cancelEdgeDwell();
      return;
    }
    if (_edgeDwellDirection == direction) return;

    _cancelEdgeDwell();
    _edgeDwellDirection = direction;
    _edgeDwellTimer = Timer(_edgeDwellDuration, () {
      final pagedDirection = direction!;
      _edgeDwellTimer = null;
      _edgeDwellDirection = null;
      unawaited(_animateBy(pagedDirection));
      _handleDragPointer(ref.read(dragStateProvider));
    });
  }

  void _cancelEdgeDwell() {
    _edgeDwellTimer?.cancel();
    _edgeDwellTimer = null;
    _edgeDwellDirection = null;
  }

  /// Rebuilds [_pageController] anchored to a fresh start date matching
  /// [newDaysPerPage], keeping the currently selected date visible. Called
  /// when the viewport crosses [_weekBreakpoint] and the meaning of "one
  /// page" changes between a day and a week.
  void _resyncForDaysPerPage(int newDaysPerPage) {
    if (!mounted) return;
    final selected = ref.read(selectedDateProvider);
    final newAnchor = newDaysPerPage == 7
        ? startOfWeek(
            selected,
            firstDayOfWeek: ref.read(daySettingsProvider).firstDayOfWeek,
          )
        : selected;

    _pageController.dispose();
    setState(() {
      _daysPerPage = newDaysPerPage;
      _anchorDate = newAnchor;
      _pageController = PageController(initialPage: _pageSpread);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(daySettingsProvider);
    final daysPerPage = _daysPerPage!;

    ref.listen<DragState?>(dragStateProvider, (_, next) {
      _handleDragPointer(next);
    });

    return Scaffold(
      appBar: AppBar(
        // Reserves the leading slot so AppShell's floating hamburger button
        // (narrow widths only) has room without covering the title.
        leading: const SizedBox(),
        title: const Text('Day Frame'),
        actions: [
          IconButton(
            tooltip: 'Add block',
            icon: const Icon(Icons.add),
            onPressed: () => unawaited(_createViaButton(context)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wantedDaysPerPage = _daysPerPageFor(constraints.maxWidth);
          if (wantedDaysPerPage != daysPerPage && !_resyncScheduled) {
            _resyncScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _resyncScheduled = false;
              if (!mounted) return;
              _resyncForDaysPerPage(wantedDaysPerPage);
            });
          }

          return Stack(
            children: [
              PageView.builder(
                // Forces a fresh Scrollable element (and thus a fresh
                // scroll position) whenever _pageController is swapped in
                // _resyncForDaysPerPage. Without this, Flutter absorbs the
                // outgoing controller's raw pixel offset into the new one,
                // silently overriding the new controller's initialPage and
                // landing on the wrong day/week.
                key: ObjectKey(_pageController),
                controller: _pageController,
                // Disables PageView's own gesture recognizer (so it never
                // competes for drags that start on a block) while keeping
                // PageScrollPhysics' snap-to-page ballistic simulation for
                // drags forwarded manually from DayGrid's own detector —
                // see _onSwipeStart/_onSwipeEnd.
                physics: const NeverScrollableScrollPhysics(
                  parent: PageScrollPhysics(),
                ),
                onPageChanged: _onPageChanged,
                itemBuilder: (context, page) => _SchedulePage(
                  startDate: _startDateForPage(page),
                  dayCount: daysPerPage,
                  settings: settings,
                  onSwipeStart: _onSwipeStart,
                  onSwipeUpdate: _onSwipeUpdate,
                  onSwipeEnd: _onSwipeEnd,
                  onSwipeCancel: _onSwipeCancel,
                ),
              ),
              // Fades the sliding date label(s) to the background color
              // before they reach either arrow, so they never visibly
              // overlap one.
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
              // Fixed in place (outside the PageView) so only the page
              // content slides.
              Positioned(
                top: 0,
                left: 8,
                height: scheduleHeaderHeight,
                child: IconButton(
                  tooltip: daysPerPage == 7 ? 'Previous week' : 'Previous day',
                  icon: const Icon(Icons.chevron_left),
                  style: IconButton.styleFrom(
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                  onPressed: () => unawaited(_animateBy(-1)),
                ),
              ),
              Positioned(
                top: 0,
                right: 8,
                height: scheduleHeaderHeight,
                child: IconButton(
                  tooltip: daysPerPage == 7 ? 'Next week' : 'Next day',
                  icon: const Icon(Icons.chevron_right),
                  style: IconButton.styleFrom(
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                  onPressed: () => unawaited(_animateBy(1)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One page of [DayScreen]: [dayCount] day columns (1 in day view, 7 in
/// week view) starting at [startDate], each with its own date header and
/// [DayGrid], laid out via the shared [ScheduleColumnsPage].
///
/// The switch arrows are drawn separately, fixed in place outside the
/// [PageView] this is built by.
class _SchedulePage extends ConsumerWidget {
  const new({
    required this.startDate,
    required this.dayCount,
    required this.settings,
    required this.onSwipeStart,
    required this.onSwipeUpdate,
    required this.onSwipeEnd,
    required this.onSwipeCancel,
  });

  final DateTime startDate;
  final int dayCount;
  final DaySettings settings;
  final GestureDragStartCallback onSwipeStart;
  final GestureDragUpdateCallback onSwipeUpdate;
  final GestureDragEndCallback onSwipeEnd;
  final VoidCallback onSwipeCancel;

  TextStyle? _headerStyle(BuildContext context, DateTime date) {
    final base = Theme.of(context).textTheme.titleMedium;
    if (!isSameDay(date, DateTime.now())) return base;
    return base?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = List.generate(
      dayCount,
      (i) => DateTime(startDate.year, startDate.month, startDate.day + i),
    );

    return ScheduleColumnsPage(
      columnCount: dayCount,
      settings: settings,
      headerBuilder: (context, i) {
        final date = dates[i];
        final label = Text(
          key: dayCount == 1
              ? const Key('day-screen-date-label')
              : Key('day-screen-date-label-${date.toIso8601String()}'),
          formatDayHeaderLabel(
            date,
            showWeekday: dayCount == 1,
            pattern: settings.dateFormat,
          ),
          style: _headerStyle(context, date),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );

        if (dayCount > 1) {
          // Week-view columns are narrow, so the apply-template button
          // (hover-only here) overlays the cell instead of reserving Row
          // space — reserving space for it left the date text with barely
          // half the column's width to work with.
          return Semantics(
            header: true,
            container: true,
            child: Stack(
              alignment: Alignment.center,
              children: [
                label,
                Align(
                  alignment: Alignment.centerRight,
                  child: ApplyTemplateButton(date: date, alwaysVisible: false),
                ),
              ],
            ),
          );
        }

        final trailingCluster = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 4),
            ApplyTemplateButton(date: date, alwaysVisible: true),
          ],
        );
        // A plain Row would center the label-plus-button pair as a
        // whole, pushing the date text itself off-center by roughly
        // half the button's width. Mirroring an identically-sized,
        // invisible copy of the trailing button cluster on the leading
        // side keeps the whole row symmetric around the label, so the
        // label itself lands back on the header's true center.
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: trailingCluster,
            ),
            Flexible(child: label),
            trailingCluster,
          ],
        );
      },
      gridBuilder: (context, i, slotHeight, {required showHourLabels}) =>
          _buildColumn(context, ref, dates[i], slotHeight, showHourLabels),
    );
  }

  Widget _buildColumn(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
    double slotHeight,
    bool showHourLabels,
  ) {
    final blocksAsync = ref.watch(dayBlocksProvider(date));
    final applyEffects = ref.watch(templateApplyEffectsProvider(date));
    final applyEffectsNotifier = ref.read(
      templateApplyEffectsProvider(date).notifier,
    );

    return Expanded(
      child: blocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load: $error')),
        data: (blocks) => DayGrid(
          key: scheduleGridKeyFor(DayColumn(date)),
          date: date,
          column: DayColumn(date),
          controller: const DayScheduleController(),
          actions: dayScheduleBlockActions,
          blocks: blocks,
          settings: settings,
          slotHeight: slotHeight,
          showHourLabels: showHourLabels,
          onSwipeStart: onSwipeStart,
          onSwipeUpdate: onSwipeUpdate,
          onSwipeEnd: onSwipeEnd,
          onSwipeCancel: onSwipeCancel,
          highlightedBlockIds: applyEffects.highlightedIds,
          ghosts: applyEffects.ghosts,
          onHighlightAnimationEnd: applyEffectsNotifier.removeHighlight,
          onGhostAnimationEnd: applyEffectsNotifier.removeGhost,
          onCreateBlock: ({required start, required end, required kind}) {
            unawaited(
              _createAndOpen(
                context,
                ref,
                date,
                start: start,
                end: end,
                kind: kind,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _createAndOpen(
    BuildContext context,
    WidgetRef ref,
    DateTime date, {
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
  }) async {
    final created = await ref
        .read(dayBlocksProvider(date).notifier)
        .addBlock(start: start, end: end, kind: kind);
    if (!context.mounted) return;
    await showBlockEditModal(
      context: context,
      column: DayColumn(date),
      actions: dayScheduleBlockActions,
      block: created,
    );
  }
}
