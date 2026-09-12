import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:taskframe/features/day/day_grid_sizing.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/widgets/hour_gutter.dart';

/// Height of the header row shared by every paged schedule screen
/// (`DayScreen`, `TemplatesScreen`) — both the fixed switch arrows and
/// each page's own header content align to this.
const scheduleHeaderHeight = 56.0;

/// Width of the fade strip behind each switch arrow, wide enough to fully
/// obscure sliding header content before it reaches the arrow.
const scheduleEdgeFadeWidth = 72.0;

/// Shared page-turn animation, used by every "Previous"/"Next" arrow.
const schedulePageAnimationDuration = Duration(milliseconds: 250);

/// See [schedulePageAnimationDuration].
const Curve schedulePageAnimationCurve = Curves.easeOut;

/// Below this, a 15-minute slot stops being visually distinct, so the grid
/// scrolls instead of shrinking further.
const _minSlotHeight = 8.0;

/// Horizontal gap between adjacent columns, both in the grid and (as the
/// divider's total width) in the header.
const _columnGap = 8.0;

/// One page of a paged schedule screen: a header row above a scrollable
/// grid row, both laid out as [columnCount] side-by-side columns sharing
/// the same [HourGutter]-width spacers and dividers.
///
/// Used by both `DayScreen` (columns = dates) and `TemplatesScreen`
/// (columns = templates) so their chrome can't drift apart the way it did
/// before this was extracted — each screen supplies only its own header
/// and grid content via [headerBuilder]/[gridBuilder].
///
/// A single column ([columnCount] == 1) skips the flanking [HourGutter]
/// widgets and inter-column divider entirely: the header centers its
/// content across the full width, and [gridBuilder] is told (via the
/// `showHourLabels` argument it's called with) to have its grid draw its
/// own internal hour labels instead.
class ScheduleColumnsPage extends StatelessWidget {
  /// Creates a [ScheduleColumnsPage].
  const new({
    required this.columnCount,
    required this.settings,
    required this.headerBuilder,
    required this.gridBuilder,
    super.key,
  });

  /// How many columns this page shows.
  final int columnCount;

  /// The grid's visible start/end hours, shared by every column.
  final DaySettings settings;

  /// Builds column `index`'s header content, centered within its cell.
  final Widget Function(BuildContext context, int index) headerBuilder;

  /// Builds column `index`'s grid content, already wrapped in its own
  /// sizing widget (e.g. `Expanded`) — called with whether its grid should
  /// draw its own hour labels (true only when [columnCount] == 1, in
  /// which case no flanking [HourGutter] is drawn separately).
  final Widget Function(
    BuildContext context,
    int index,
    double slotHeight, {
    required bool showHourLabels,
  })
  gridBuilder;

  bool get _showHourLabels => columnCount == 1;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          SizedBox(
            height: scheduleHeaderHeight,
            child: columnCount == 1
                ? Center(child: headerBuilder(context, 0))
                : Row(
                    children: [
                      const SizedBox(width: HourGutter.width),
                      for (var i = 0; i < columnCount; i++) ...[
                        if (i > 0)
                          VerticalDivider(
                            width: _columnGap,
                            thickness: 1,
                            indent: scheduleHeaderHeight / 4,
                            endIndent: scheduleHeaderHeight / 4,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        Expanded(
                          child: Center(child: headerBuilder(context, i)),
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
                      for (var i = 0; i < columnCount; i++) ...[
                        if (i > 0) const SizedBox(width: _columnGap),
                        gridBuilder(
                          context,
                          i,
                          slotHeight,
                          showHourLabels: _showHourLabels,
                        ),
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
}

/// A gradient strip fading from transparent to the scaffold's background
/// color, from the header's center-ward side toward the [alignLeft] or
/// right screen edge — masks sliding header content near a switch arrow
/// so it never visibly overlaps one. Used by both `DayScreen` and
/// `TemplatesScreen`.
class ScheduleEdgeFade extends StatelessWidget {
  /// Creates a [ScheduleEdgeFade].
  const new({required this.alignLeft, super.key});

  /// Whether this fade sits at the left edge (fading toward the right) or
  /// the right edge (fading toward the left).
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

/// Forwards a raw horizontal drag — one starting on a `DayGrid`'s free
/// space, via its `onSwipeStart`/`onSwipeUpdate`/`onSwipeEnd`/
/// `onSwipeCancel` callbacks — into [pageController]'s own scroll
/// position, so dragging the grid pages the screen exactly like dragging
/// the `PageView` itself would. Used by `TemplatesScreen` to give its
/// narrow-width paging real swipe support.
class PageSwipeForwarder {
  /// Creates a [PageSwipeForwarder] for [pageController].
  new(this.pageController);

  /// The controller drags are forwarded into.
  PageController pageController;

  Drag? _drag;

  /// Forwards a swipe's [DragStartDetails] — pass as a `DayGrid`'s
  /// `onSwipeStart`.
  void onSwipeStart(DragStartDetails details) {
    _drag = pageController.position.drag(details, () => _drag = null);
  }

  /// Forwards a swipe's [DragUpdateDetails] — pass as a `DayGrid`'s
  /// `onSwipeUpdate`.
  void onSwipeUpdate(DragUpdateDetails details) => _drag?.update(details);

  /// Forwards a swipe's [DragEndDetails] — pass as a `DayGrid`'s
  /// `onSwipeEnd`.
  void onSwipeEnd(DragEndDetails details) {
    _drag?.end(details);
    _drag = null;
  }

  /// Cancels the in-flight forwarded drag, if any — pass as a `DayGrid`'s
  /// `onSwipeCancel`.
  void onSwipeCancel() {
    _drag?.cancel();
    _drag = null;
  }
}
