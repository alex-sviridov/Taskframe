import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/date_format.dart';
import 'package:taskframe/features/day/day_grid_sizing.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/week_utils.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
import 'package:taskframe/features/day/widgets/hour_gutter.dart';

/// Below this, a 15-minute slot stops being visually distinct, so the grid
/// scrolls instead of shrinking further.
const _minSlotHeight = 8.0;

/// Half the page-index range paged over by [_DayScreenState._pageController],
/// centered on the date shown when the screen first builds. Gives roughly
/// 270 years of swiping in either direction.
const _pageSpread = 100000;

const _pageAnimationDuration = Duration(milliseconds: 250);
const Curve _pageAnimationCurve = Curves.easeOut;

/// Height of the date header row, shared by the fixed switch arrows and
/// each page's date label(s) so they stay vertically aligned.
const _headerHeight = 56.0;

/// Width of the fade strip behind each switch arrow, wide enough to fully
/// obscure the sliding date label before it reaches the arrow.
const _edgeFadeWidth = 72.0;

/// How long the drag pointer must stay in an edge zone before it pages to
/// the adjacent day/week.
const _edgeDwellDuration = Duration(milliseconds: 600);

/// Viewport width at/above which the schedule shows a full week (7 days)
/// per page instead of a single day.
const _weekBreakpoint = 900.0;

/// Horizontal gap between adjacent day columns in week view, both in the
/// grid and (as the divider's total width) in the header.
const _columnGap = 8.0;

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
      duration: _pageAnimationDuration,
      curve: _pageAnimationCurve,
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

    final width = MediaQuery.sizeOf(context).width;
    final dx = drag.pointerGlobalPosition.dx;
    int? direction;
    if (dx <= _edgeFadeWidth) {
      direction = -1;
    } else if (dx >= width - _edgeFadeWidth) {
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
      appBar: AppBar(title: const Text('Day Frame')),
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
                width: _edgeFadeWidth,
                height: _headerHeight,
                child: IgnorePointer(child: _EdgeFade(alignLeft: true)),
              ),
              const Positioned(
                top: 0,
                right: 0,
                width: _edgeFadeWidth,
                height: _headerHeight,
                child: IgnorePointer(child: _EdgeFade(alignLeft: false)),
              ),
              // Fixed in place (outside the PageView) so only the page
              // content slides.
              Positioned(
                top: 0,
                left: 8,
                height: _headerHeight,
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
                height: _headerHeight,
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

/// A gradient strip fading from transparent to the scaffold's background
/// color, from the header's center-ward side toward the [alignLeft] or
/// right screen edge, masking the sliding date label near a switch arrow.
class _EdgeFade extends StatelessWidget {
  const new({required this.alignLeft});

  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: alignLeft ? Alignment.centerRight : Alignment.centerLeft,
          end: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
          colors: [background.withValues(alpha: 0), background],
        ),
      ),
    );
  }
}

/// One page of [DayScreen]: [dayCount] day columns (1 in day view, 7 in
/// week view) starting at [startDate], each with its own date header and
/// [DayGrid].
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

  bool get _showHourLabels => dayCount == 1;

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  TextStyle? _headerStyle(BuildContext context, DateTime date) {
    final base = Theme.of(context).textTheme.titleMedium;
    if (!_isToday(date)) return base;
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          SizedBox(
            height: _headerHeight,
            child: dayCount == 1
                ? Center(
                    child: Text(
                      key: const Key('day-screen-date-label'),
                      formatDayHeaderLabel(
                        dates.first,
                        showWeekday: true,
                        pattern: settings.dateFormat,
                      ),
                      style: _headerStyle(context, dates.first),
                    ),
                  )
                : Row(
                    children: [
                      const SizedBox(width: HourGutter.width),
                      for (var i = 0; i < dates.length; i++) ...[
                        if (i > 0)
                          VerticalDivider(
                            width: _columnGap,
                            thickness: 1,
                            indent: _headerHeight / 4,
                            endIndent: _headerHeight / 4,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        Expanded(
                          child: Center(
                            child: Semantics(
                              header: true,
                              container: true,
                              child: Text(
                                key: Key(
                                  'day-screen-date-label-'
                                  '${dates[i].toIso8601String()}',
                                ),
                                formatDayHeaderLabel(
                                  dates[i],
                                  showWeekday: false,
                                  pattern: settings.dateFormat,
                                ),
                                style: _headerStyle(context, dates[i]),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: HourGutter.width),
                    ],
                  ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
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
                      if (!_showHourLabels)
                        HourGutter(settings: settings, slotHeight: slotHeight),
                      for (var i = 0; i < dates.length; i++) ...[
                        if (i > 0) const SizedBox(width: _columnGap),
                        _buildColumn(ref, dates[i], slotHeight),
                      ],
                      if (!_showHourLabels)
                        HourGutter(settings: settings, slotHeight: slotHeight),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn(WidgetRef ref, DateTime date, double slotHeight) {
    final blocksAsync = ref.watch(dayBlocksProvider(date));

    return Expanded(
      child: blocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load: $error')),
        data: (blocks) => DayGrid(
          key: dayGridKeyFor(date),
          date: date,
          blocks: blocks,
          settings: settings,
          slotHeight: slotHeight,
          showHourLabels: _showHourLabels,
          pageDates: List.generate(
            dayCount,
            (i) => DateTime(startDate.year, startDate.month, startDate.day + i),
          ),
          onSwipeStart: onSwipeStart,
          onSwipeUpdate: onSwipeUpdate,
          onSwipeEnd: onSwipeEnd,
          onSwipeCancel: onSwipeCancel,
          onCreateBlock: ({required start, required end, required kind}) {
            unawaited(
              ref
                  .read(dayBlocksProvider(date).notifier)
                  .addBlock(start: start, end: end, kind: kind),
            );
          },
        ),
      ),
    );
  }
}
