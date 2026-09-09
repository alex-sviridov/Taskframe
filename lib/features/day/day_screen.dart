import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/date_format.dart';
import 'package:taskframe/features/day/day_grid_sizing.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';

/// Below this, a 15-minute slot stops being visually distinct, so the grid
/// scrolls instead of shrinking further.
const _minSlotHeight = 8.0;

/// Half the page-index range paged over by [_DayScreenState._pageController],
/// centered on the date shown when the screen first builds. Gives roughly
/// 270 years of swiping in either direction.
const _pageSpread = 100000;

const _pageAnimationDuration = Duration(milliseconds: 250);
const Curve _pageAnimationCurve = Curves.easeOut;

/// Height of the date header, shared by the fixed switch arrows and each
/// page's date label so they stay vertically aligned.
const _headerHeight = 56.0;

/// Width of the fade strip behind each switch arrow, wide enough to fully
/// obscure the sliding date label before it reaches the arrow.
const _edgeFadeWidth = 72.0;

/// The day view: a date header with switch arrows above a 15-minute grid
/// of the day's blocks, paged with a finger-tracked slide animation.
class DayScreen extends ConsumerStatefulWidget {
  /// Creates a [DayScreen].
  const new({super.key});

  @override
  ConsumerState<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends ConsumerState<DayScreen> {
  late final PageController _pageController;
  late final DateTime _anchorDate;
  Drag? _drag;

  @override
  void initState() {
    super.initState();
    _anchorDate = ref.read(selectedDateProvider);
    _pageController = PageController(initialPage: _pageSpread);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _dateForPage(int page) =>
      _anchorDate.add(Duration(days: page - _pageSpread));

  void _onPageChanged(int page) {
    ref.read(selectedDateProvider.notifier).date = _dateForPage(page);
  }

  Future<void> _animateBy(int days) async {
    final page = (_pageController.page ?? _pageController.initialPage)
        .round();
    await _pageController.animateToPage(
      page + days,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Day Frame')),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            // Disables PageView's own gesture recognizer (so it never
            // competes for drags that start on a block) while keeping
            // PageScrollPhysics' snap-to-page ballistic simulation for
            // drags forwarded manually from DayGrid's own detector — see
            // _onSwipeStart/_onSwipeEnd.
            physics: const NeverScrollableScrollPhysics(
              parent: PageScrollPhysics(),
            ),
            onPageChanged: _onPageChanged,
            itemBuilder: (context, page) =>
                _DayPage(
                  date: _dateForPage(page),
                  onSwipeStart: _onSwipeStart,
                  onSwipeUpdate: _onSwipeUpdate,
                  onSwipeEnd: _onSwipeEnd,
                  onSwipeCancel: _onSwipeCancel,
                ),
          ),
          // Fades the sliding date label to the background color before it
          // reaches either arrow, so it never visibly overlaps one.
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
          // Fixed in place (outside the PageView) so only the date label
          // and grid slide with the page.
          Positioned(
            top: 0,
            left: 8,
            height: _headerHeight,
            child: IconButton(
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => unawaited(_animateBy(-1)),
            ),
          ),
          Positioned(
            top: 0,
            right: 8,
            height: _headerHeight,
            child: IconButton(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => unawaited(_animateBy(1)),
            ),
          ),
        ],
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

/// One page of [DayScreen]: the date label and grid for a single [date].
///
/// The switch arrows are drawn separately, fixed in place outside the
/// [PageView] this is built by.
class _DayPage extends ConsumerWidget {
  const new({
    required this.date,
    required this.onSwipeStart,
    required this.onSwipeUpdate,
    required this.onSwipeEnd,
    required this.onSwipeCancel,
  });

  final DateTime date;
  final GestureDragStartCallback onSwipeStart;
  final GestureDragUpdateCallback onSwipeUpdate;
  final GestureDragEndCallback onSwipeEnd;
  final VoidCallback onSwipeCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(daySettingsProvider);
    final blocksAsync = ref.watch(dayBlocksProvider(date));

    return Column(
      children: [
        SizedBox(
          height: _headerHeight,
          child: Center(
            child: Text(
              key: const Key('day-screen-date-label'),
              formatDayLabel(date),
              style: Theme.of(context).textTheme.titleMedium,
            ),
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

              return blocksAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Center(child: Text('Failed to load: $error')),
                data: (blocks) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DayGrid(
                    date: date,
                    blocks: blocks,
                    settings: settings,
                    slotHeight: slotHeight,
                    onSwipeStart: onSwipeStart,
                    onSwipeUpdate: onSwipeUpdate,
                    onSwipeEnd: onSwipeEnd,
                    onSwipeCancel: onSwipeCancel,
                    onCreateBlock:
                        ({required start, required end, required kind}) {
                          unawaited(
                            ref
                                .read(dayBlocksProvider(date).notifier)
                                .addBlock(start: start, end: end, kind: kind),
                          );
                        },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
