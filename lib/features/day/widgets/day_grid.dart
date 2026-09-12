import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
import 'package:taskframe/features/day/template_apply_effects.dart';
import 'package:taskframe/features/day/week_utils.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';
import 'package:taskframe/features/day/widgets/block_kind_style.dart';
import 'package:taskframe/features/day/widgets/block_view.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';
import 'package:taskframe/features/day/widgets/schedule_block_actions.dart';

/// The 15-minute-aligned timeline: an hour grid with [blocks] drawn on top.
///
/// Double-tapping (desktop) or long-pressing (touch) free grid space opens a
/// draft for a new block there; tapping one of [_DraftOverlay]'s two icon
/// buttons creates it via [onCreateBlock], and tapping elsewhere dismisses
/// the draft.
class DayGrid extends ConsumerStatefulWidget {
  /// Creates a [DayGrid] showing [blocks] between [settings]'s day start
  /// and day end, with each 15-minute slot [slotHeight] pixels tall.
  const new({
    required this.date,
    required this.column,
    required this.controller,
    required this.actions,
    required this.blocks,
    required this.settings,
    required this.slotHeight,
    required this.onCreateBlock,
    this.showHourLabels = true,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
    this.onSwipeCancel,
    this.highlightedBlockIds = const {},
    this.ghosts = const [],
    this.onHighlightAnimationEnd,
    this.onGhostAnimationEnd,
    super.key,
  });

  /// The date this grid shows, used to resolve tap positions into times
  /// and to drive the "now" line — for a template column this is always
  /// [templateAnchorDate], so the "now" line never applies.
  final DateTime date;

  /// This grid's column identity — used for provider/key lookups and as
  /// the drag/resize origin, independent of [date].
  final ScheduleColumn column;

  /// Reads/moves this column's blocks during a drag or resize, supplied
  /// by the caller (`DayScreen` or `TemplatesScreen`) so this widget never
  /// needs to know which feature it's showing.
  final ScheduleController controller;

  /// Supplies the block-edit modal's read/write access to this column's
  /// blocks, supplied by the same caller as [controller].
  final ScheduleBlockActions actions;

  /// The blocks to draw on the grid.
  final List<TimeObject> blocks;

  /// The grid's visible start/end hours.
  final DaySettings settings;

  /// Pixel height of a single 15-minute slot.
  final double slotHeight;

  /// Whether this grid draws its own hour-label gutter on the left.
  ///
  /// `false` in week view, where a single `HourGutter` draws the labels
  /// once for all day columns; this grid still draws its own horizontal
  /// gridlines regardless.
  final bool showHourLabels;

  /// Called when the user confirms a new block from the draft.
  final void Function({
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
  })
  onCreateBlock;

  /// Forwarded from a horizontal drag that starts on free grid space (not
  /// on a block), so the caller can drive its own day-switching animation
  /// finger-tracked. `null` disables day-switching entirely.
  final GestureDragStartCallback? onSwipeStart;

  /// See [onSwipeStart].
  final GestureDragUpdateCallback? onSwipeUpdate;

  /// See [onSwipeStart].
  final GestureDragEndCallback? onSwipeEnd;

  /// See [onSwipeStart].
  final VoidCallback? onSwipeCancel;

  /// Ids of [blocks] currently playing their newly-applied-template border
  /// pulse — see `template_apply_effects.dart`. Empty for any grid not
  /// driven by a template apply (e.g. every `TemplatesScreen` column).
  final Set<String> highlightedBlockIds;

  /// Skipped template events currently playing their "not applied" ghost
  /// animation at their would-be slot.
  final List<TemplateApplyGhost> ghosts;

  /// Called once a highlighted block's pulse animation finishes, so the
  /// caller can drop it from [highlightedBlockIds].
  final void Function(String blockId)? onHighlightAnimationEnd;

  /// Called once a ghost's animation finishes, so the caller can drop it
  /// from [ghosts].
  final void Function(int ghostId)? onGhostAnimationEnd;

  @override
  ConsumerState<DayGrid> createState() => _DayGridState();
}

class _DayGridState extends ConsumerState<DayGrid> {
  ({DateTime start, DateTime end})? _draft;
  Timer? _nowTimer;

  @override
  void initState() {
    super.initState();
    _scheduleNowTimer();
  }

  @override
  void didUpdateWidget(DayGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _scheduleNowTimer();
    }
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    super.dispose();
  }

  /// Redraws once a minute while [widget.date] is today, so the
  /// current-time marker line keeps moving; does nothing otherwise.
  void _scheduleNowTimer() {
    _nowTimer?.cancel();
    _nowTimer = _isToday
        ? Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}))
        : null;
  }

  bool get _isToday => isSameDay(widget.date, DateTime.now());

  int get _slotCount =>
      (widget.settings.dayEndHour - widget.settings.dayStartHour) * 4;

  double get _dayStartInMinutes => widget.settings.dayStartHour * 60;

  double get _gridLeft => widget.showHourLabels ? 44 : 4;

  double _offsetFor(DateTime time) {
    final minutesFromStart = time.hour * 60 + time.minute - _dayStartInMinutes;
    return minutesFromStart / 15 * widget.slotHeight;
  }

  /// True height of the landzone drag preview: [block]'s own duration,
  /// measured from [start].
  double _landzoneHeightFor(DateTime start, TimeObject block) =>
      _offsetFor(start.add(block.end.difference(block.start))) -
      _offsetFor(start);

  List<TimeObject> get _blocksSortedByStart =>
      [...widget.blocks]..sort((a, b) => a.start.compareTo(b.start));

  /// Height of a block's title-overlay box — enough for one `bodySmall`
  /// line plus its padding, regardless of the block's own true duration.
  /// See [_titleOverlay] for why this can't just be the block's own
  /// height.
  static const double _titleOverlayHeight = 20;

  /// One block's title, drawn in a box [_titleOverlayHeight] tall — taller
  /// than [trueHeight] whenever the block itself is short — so Flutter
  /// web, which clips a `Positioned` child's paint to its own box (unlike
  /// native Flutter, there is no free overflow past a too-short box),
  /// never clips the title to nothing. A block tall enough to contain that
  /// box keeps the title pinned to its own top-left corner, matching every
  /// other block; a too-short block instead gets the box centered on its
  /// own true vertical midpoint, so the title reads as centered on the
  /// block rather than hanging off its top edge. Used for the static grid
  /// blocks, the landzone drag preview, and the resize-draft preview
  /// alike, so a too-short block's title survives being dragged or
  /// resized exactly as it survives sitting still.
  Widget _titleOverlay({
    required Key key,
    required TimeObject block,
    required double trueTop,
    required double trueHeight,
  }) {
    final isShort = trueHeight < _titleOverlayHeight;
    final boxTop = isShort
        ? trueTop + trueHeight / 2 - _titleOverlayHeight / 2
        : trueTop;
    final category = _categoryFor(block);

    return Positioned(
      key: key,
      top: boxTop,
      left: _gridLeft,
      right: 0,
      height: _titleOverlayHeight,
      child: IgnorePointer(
        child: Padding(
          // A tall block keeps its title hugging the top-left corner
          // (minimal top inset); a too-short block's box is already
          // centered on the block above, so its text is centered within
          // that box too rather than hugging its own top.
          padding: EdgeInsets.only(left: 6, right: 6, top: isShort ? 0 : 1),
          child: Align(
            alignment: isShort ? Alignment.centerLeft : Alignment.topLeft,
            child: Text(
              category?.formatTitle(block.title) ?? block.title,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  /// The category [block] is tagged with, resolved from the currently
  /// loaded category list, or `null` while categories are still loading.
  Category? _categoryFor(TimeObject block) {
    final categories = ref.watch(categoryListProvider).value;
    if (categories == null) return null;
    return categoryById(categories, block.categoryId);
  }

  void _openDraftAt(double dy) {
    final start = slotStartForOffset(
      day: widget.date,
      dy: dy,
      settings: widget.settings,
      slotHeight: widget.slotHeight,
    );
    if (start == null) return;

    final duration = durationForNewBlock(
      slotStart: start,
      existingBlocks: widget.blocks,
      settings: widget.settings,
    );
    setState(() => _draft = (start: start, end: start.add(duration)));
  }

  void _dismissDraft() {
    if (_draft != null) {
      setState(() => _draft = null);
    }
  }

  void _openEditModal(TimeObject block) {
    unawaited(
      showBlockEditModal(
        context: context,
        column: widget.column,
        actions: widget.actions,
        block: block,
      ),
    );
  }

  void _create(BlockKind kind) {
    final draft = _draft!;
    widget.onCreateBlock(start: draft.start, end: draft.end, kind: kind);
    setState(() => _draft = null);
  }

  /// Wraps [child] in the newly-applied-template border pulse when [block]
  /// is one of [DayGrid.highlightedBlockIds], otherwise returns it as-is.
  Widget _maybeHighlighted({required TimeObject block, required Widget child}) {
    if (!widget.highlightedBlockIds.contains(block.id)) return child;
    return _TemplateHighlightPulse(
      key: Key('day-grid-highlight-${block.id}'),
      onDone: () => widget.onHighlightAnimationEnd?.call(block.id),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = _slotCount * widget.slotHeight;
    final draft = _draft;
    // Selected rather than watched outright: a plain `ref.watch` here would
    // rebuild every visible `DayGrid` column on every pointer move of a drag
    // or resize happening on some other day (most columns, in week view).
    // `dragStateForColumn`/`resizeStateForColumn` collapse to `null` for a
    // column the in-flight gesture doesn't touch, and `null == null`, so
    // `select` skips the rebuild there entirely.
    final dragState = ref.watch(
      dragStateProvider.select(
        (state) => dragStateForColumn(state, widget.column),
      ),
    );
    final resizeState = ref.watch(
      resizeStateProvider.select(
        (state) => resizeStateForColumn(state, widget.column),
      ),
    );
    final hiddenBlockId =
        dragState != null && dragState.originalColumn == widget.column
        ? dragState.block.id
        : resizeState != null && resizeState.column == widget.column
        ? resizeState.block.id
        : null;
    // `dragState.targetColumn`/`targetStart` fall back to the block's own
    // original column/time whenever the pointer is over no valid column
    // (see DragNotifier._handlePointerEvent), so the shadow previews the
    // snap-back on the origin column instead of vanishing — releasing there
    // still cancels the move, this just shows where the block would land.
    final landzoneStart =
        dragState != null && dragState.targetColumn == widget.column
        ? dragState.targetStart
        : null;
    final nowOffset = _isToday ? _offsetFor(DateTime.now()) : null;
    final nowLineY = nowOffset != null && nowOffset >= 0 && nowOffset <= height
        ? nowOffset
        : null;
    final resizeBleed = resizeBleedForBlocks(
      blocks: widget.blocks,
      offsetFor: _offsetFor,
      maxBleed: _DraggableBlock.hitBleed,
    );

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            // Only the background layer reacts to gestures: blocks (and the
            // draft overlay) are drawn above it in this Stack and, being
            // opaque, absorb touches that start on them before they ever
            // reach this GestureDetector.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissDraft,
              onDoubleTapDown: (details) =>
                  _openDraftAt(details.localPosition.dy),
              onLongPressStart: (details) =>
                  _openDraftAt(details.localPosition.dy),
              onHorizontalDragStart: widget.onSwipeStart,
              onHorizontalDragUpdate: widget.onSwipeUpdate,
              onHorizontalDragEnd: widget.onSwipeEnd,
              onHorizontalDragCancel: widget.onSwipeCancel,
              child: CustomPaint(
                painter: _DayGridPainter(
                  settings: widget.settings,
                  slotHeight: widget.slotHeight,
                  lineColor: scheme.outlineVariant,
                  labelStyle: Theme.of(context).textTheme.labelSmall,
                  gridLeft: _gridLeft,
                  showLabels: widget.showHourLabels,
                ),
              ),
            ),
          ),
          for (final block in widget.blocks)
            Positioned(
              key: ValueKey('day-grid-block-position-${block.id}'),
              // Enlarged by up to `_DraggableBlock.hitBleed` on each
              // side — clamped per [resizeBleedForBlocks] so a
              // time-adjacent neighbor's true bounds are never intruded
              // on — giving the touch resize zone (and, on a very short
              // block, the mouse resize strips) room to bleed past the
              // block's true edges. Hit-testing gates on a render
              // object's own reported size, so that bleed only works if
              // it's baked in here rather than attempted via `Clip.none`
              // alone. `_DraggableBlock` insets its real visual content
              // back to the true, unbled bounds.
              top: _offsetFor(block.start) - (resizeBleed[block.id]?.top ?? 0),
              left: _gridLeft,
              right: 0,
              height:
                  _offsetFor(block.end) -
                  _offsetFor(block.start) +
                  (resizeBleed[block.id]?.top ?? 0) +
                  (resizeBleed[block.id]?.bottom ?? 0),
              // Stays mounted even while its own drag is in progress
              // (rather than being filtered out of this loop), so the
              // recognizer that detected the drag's start is not disposed
              // out from under the gesture; only its visible content is
              // swapped for an empty placeholder, leaving the landzone
              // shadow to represent the block's drag position instead.
              //
              // The placeholder is invisible, not inert: this Positioned
              // still gives _DraggableBlock's opaque detector a hit-test
              // region at the block's original rect for the duration of
              // the drag. Harmless in practice — the landzone painted over
              // it is IgnorePointer-wrapped, and a stray tap here only
              // no-ops through _dismissDraft.
              child: _DraggableBlock(
                block: block,
                column: widget.column,
                controller: widget.controller,
                date: widget.date,
                settings: widget.settings,
                slotHeight: widget.slotHeight,
                topBleed: resizeBleed[block.id]?.top ?? 0,
                bottomBleed: resizeBleed[block.id]?.bottom ?? 0,
                onDismissDraft: _dismissDraft,
                onOpenEdit: _openEditModal,
                child: block.id == hiddenBlockId
                    ? const SizedBox.shrink()
                    : _maybeHighlighted(
                        block: block,
                        child: Container(
                          color: scheme.surface,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: BlockView(
                            block: block,
                            showTitle: false,
                            category: _categoryFor(block),
                          ),
                        ),
                      ),
              ),
            ),
          // Every block's title, drawn in its own layer *after* every
          // block's own box above — so a short block's title always paints
          // on top of a neighbor's box, never underneath it. Sorted by
          // start so that when two adjacent short blocks' title boxes
          // overlap, the later one wins rather than an arbitrary list
          // order.
          for (final block in _blocksSortedByStart)
            if (block.id != hiddenBlockId)
              _titleOverlay(
                key: ValueKey('day-grid-block-title-${block.id}'),
                block: block,
                trueTop: _offsetFor(block.start),
                trueHeight: _offsetFor(block.end) - _offsetFor(block.start),
              ),
          if (draft != null)
            Positioned(
              top: _offsetFor(draft.start),
              left: _gridLeft,
              right: 0,
              height: _offsetFor(draft.end) - _offsetFor(draft.start),
              child: Container(
                color: scheme.surface,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _DraftOverlay(
                  onCreateEvent: () => _create(BlockKind.anchor),
                  onCreateFrame: () => _create(BlockKind.frame),
                ),
              ),
            ),
          if (dragState != null && landzoneStart != null) ...[
            Positioned(
              key: const Key('day-grid-landzone'),
              top: _offsetFor(landzoneStart),
              left: _gridLeft,
              right: 0,
              height: _landzoneHeightFor(landzoneStart, dragState.block),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DashedBorderPainter(color: scheme.primary),
                  child: Container(
                    color: scheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: BlockView(
                      block: dragState.block,
                      showTitle: false,
                      category: _categoryFor(dragState.block),
                    ),
                  ),
                ),
              ),
            ),
            _titleOverlay(
              key: const Key('day-grid-landzone-title'),
              block: dragState.block,
              trueTop: _offsetFor(landzoneStart),
              trueHeight: _landzoneHeightFor(landzoneStart, dragState.block),
            ),
          ],
          if (resizeState != null && resizeState.column == widget.column) ...[
            Positioned(
              key: const Key('day-grid-resize-draft'),
              top: _offsetFor(resizeState.draftStart),
              left: _gridLeft,
              right: 0,
              height:
                  _offsetFor(resizeState.draftEnd) -
                  _offsetFor(resizeState.draftStart),
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DashedBorderPainter(color: scheme.primary),
                  child: Container(
                    color: scheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: BlockView(
                      block: resizeState.block,
                      showTitle: false,
                      category: _categoryFor(resizeState.block),
                    ),
                  ),
                ),
              ),
            ),
            _titleOverlay(
              key: const Key('day-grid-resize-draft-title'),
              block: resizeState.block,
              trueTop: _offsetFor(resizeState.draftStart),
              trueHeight:
                  _offsetFor(resizeState.draftEnd) -
                  _offsetFor(resizeState.draftStart),
            ),
          ],
          if (nowLineY != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _NowLinePainter(y: nowLineY)),
              ),
            ),
          for (final ghost in widget.ghosts)
            Positioned(
              key: Key('day-grid-ghost-${ghost.id}'),
              top: _offsetFor(ghost.start),
              left: _gridLeft,
              right: 0,
              height: _offsetFor(ghost.end) - _offsetFor(ghost.start),
              child: IgnorePointer(
                child: _TemplateGhostOverlay(
                  onDone: () => widget.onGhostAnimationEnd?.call(ghost.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A short border-color pulse shown around a block just added by applying
/// a template — fades from [ColorScheme.primary] back to nothing over
/// [templateApplyHighlightDuration], then calls [onDone].
class _TemplateHighlightPulse extends StatefulWidget {
  const _TemplateHighlightPulse({
    required this.onDone,
    required this.child,
    super.key,
  });

  final VoidCallback onDone;
  final Widget child;

  @override
  State<_TemplateHighlightPulse> createState() =>
      _TemplateHighlightPulseState();
}

class _TemplateHighlightPulseState extends State<_TemplateHighlightPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: templateApplyHighlightDuration,
          )
          ..addStatusListener(_handleStatus)
          ..forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 1 - _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: color.withValues(alpha: opacity),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A brief fading, side-to-side-shaking dashed outline shown at a template
/// event's would-be slot when it was skipped for overlapping an existing
/// block — plays for [templateApplyGhostDuration], then calls [onDone].
class _TemplateGhostOverlay extends StatefulWidget {
  const _TemplateGhostOverlay({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_TemplateGhostOverlay> createState() => _TemplateGhostOverlayState();
}

class _TemplateGhostOverlayState extends State<_TemplateGhostOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: templateApplyGhostDuration)
          ..addStatusListener(_handleStatus)
          ..forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.0, 1.0);
        final dx = math.sin(t * math.pi * 6) * 4 * (1 - t);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: CustomPaint(painter: _DashedBorderPainter(color: color)),
          ),
        );
      },
    );
  }
}

/// Wraps one rendered block with the gestures that *start* a drag: a
/// long-press on touch, an immediate pan on mouse/trackpad, and a plain tap
/// (forwarded to [onDismissDraft]) on any device. Locked blocks only get
/// the tap handler.
///
/// Deliberately handles only the start. Once a drag begins, [DragNotifier]
/// takes ownership of the pointer through a global pointer route and drives
/// every subsequent move/end/cancel itself — see its class docs. Wiring the
/// recognizers' own `onUpdate`/`onEnd`/`onCancel` here as well would both
/// double-handle each event and, worse, keep the drag hostage to this
/// widget's mount lifetime: an edge-triggered page turn unmounts this
/// widget mid-drag, disposing the recognizers and killing their pointer
/// route before any end callback can fire.
///
/// Which edge a touch resize grabs is decided by [resizeEdgeForLocalY]
/// rather than by fixed-size hit zones, so a block too short to fit two
/// non-overlapping zones still resolves unambiguously: [localY] is compared
/// against the block's own true midpoint, not against zone geometry.
ResizeEdge resizeEdgeForLocalY({
  required double localY,
  required double blockHeight,
}) => localY < blockHeight / 2 ? ResizeEdge.start : ResizeEdge.end;

/// How far each of [blocks] may safely bleed its hit-test region past its
/// own true top/bottom edge, without intruding into a time-adjacent
/// neighbor's true bounds.
///
/// Each block's own `_DraggableBlock` gets an opaque catch-all covering its
/// *entire* bled box (see that class's docs), so an unclamped bleed would
/// let one block's hit region silently steal pointer events meant for a
/// neighbor sitting right next to it — most visible in a densely-packed
/// part of the day, where many blocks are back-to-back or nearly so.
/// [blocks] need not be pre-sorted; this sorts its own copy by [start] to
/// find each block's true time-adjacent neighbors, independent of
/// whatever order the caller's list happens to be in.
Map<String, ({double top, double bottom})> resizeBleedForBlocks({
  required List<TimeObject> blocks,
  required double Function(DateTime) offsetFor,
  required double maxBleed,
}) {
  final sorted = [...blocks]..sort((a, b) => a.start.compareTo(b.start));
  final result = <String, ({double top, double bottom})>{};

  double halfGapClamped(double? neighborOffset, double ownOffset) {
    if (neighborOffset == null) return maxBleed;
    final gap = (ownOffset - neighborOffset).abs();
    if (gap <= 0) return 0;
    final half = gap / 2;
    return half < maxBleed ? half : maxBleed;
  }

  for (var i = 0; i < sorted.length; i++) {
    final block = sorted[i];
    final blockTop = offsetFor(block.start);
    final blockBottom = offsetFor(block.end);
    final previousEnd = i > 0 ? offsetFor(sorted[i - 1].end) : null;
    final nextStart = i < sorted.length - 1
        ? offsetFor(sorted[i + 1].start)
        : null;

    result[block.id] = (
      top: halfGapClamped(previousEnd, blockTop),
      bottom: halfGapClamped(nextStart, blockBottom),
    );
  }

  return result;
}

class _DraggableBlock extends ConsumerStatefulWidget {
  const _DraggableBlock({
    required this.block,
    required this.column,
    required this.controller,
    required this.date,
    required this.settings,
    required this.slotHeight,
    required this.topBleed,
    required this.bottomBleed,
    required this.onDismissDraft,
    required this.onOpenEdit,
    required this.child,
  });

  final TimeObject block;
  final ScheduleColumn column;
  final ScheduleController controller;
  final DateTime date;
  final DaySettings settings;
  final double slotHeight;

  /// How far this widget's touch resize zone (and, to a lesser extent, its
  /// mouse resize strips) may bleed past the block's own true top/bottom
  /// edge — computed per-block by [resizeBleedForBlocks] so it never
  /// intrudes into a time-adjacent neighbor's true bounds.
  ///
  /// Hit-testing gates on a render object's own reported size before ever
  /// descending into its children — `Clip.none` only lifts the *painting*
  /// clip, not this gate — so a child positioned outside `[0, height]`
  /// inside this widget's own `Stack` is simply never reachable by a
  /// pointer. The caller (`DayGrid`) must give this widget's own outer
  /// `Positioned` extra size equal to [topBleed]/[bottomBleed]; this widget
  /// then insets its real visual content back to the true bounds.
  final double topBleed;

  /// See [topBleed].
  final double bottomBleed;

  final VoidCallback onDismissDraft;
  final void Function(TimeObject block) onOpenEdit;
  final Widget child;

  /// The maximum either of [topBleed]/[bottomBleed] may ever be, used by
  /// `DayGrid` as the upper bound passed to [resizeBleedForBlocks].
  static const double hitBleed = 9;

  @override
  ConsumerState<_DraggableBlock> createState() => _DraggableBlockState();
}

class _DraggableBlockState extends ConsumerState<_DraggableBlock> {
  /// The id of the last pointer to go down on this block, captured from the
  /// raw event because neither `LongPressStartDetails` nor
  /// `DragStartDetails` carries it, and [DragNotifier] needs it to filter
  /// its global route down to this one gesture.
  int? _pointer;

  /// Height of the classic, precise mouse resize strip sitting right at
  /// each true edge — much smaller than touch's bleed, since a mouse
  /// pointer doesn't need a big target, and this leaves the rest of even a
  /// tiny block free for the move `PanGestureRecognizer` underneath.
  static const double _mouseStripHeight = 6;

  void _start(Offset globalPosition) {
    // Copied out of `widget` so the resolver closure outlives this State:
    // it keeps being called after a page turn unmounts this widget.
    final settings = widget.settings;
    final slotHeight = widget.slotHeight;
    final controller = widget.controller;
    final origin = widget.column;
    final blockDuration = widget.block.end.difference(widget.block.start);

    ref
        .read(dragStateProvider.notifier)
        .start(
          block: widget.block,
          originalColumn: origin,
          controller: controller,
          pointerGlobalPosition: globalPosition,
          pointer: _pointer,
          resolveTarget: (position) => resolveDragTarget(
            globalPosition: position,
            origin: origin,
            settings: settings,
            slotHeight: slotHeight,
            blockDuration: blockDuration,
          ),
        );
  }

  void _startResize(ResizeEdge edge) {
    ref
        .read(resizeStateProvider.notifier)
        .start(
          block: widget.block,
          column: widget.column,
          controller: widget.controller,
          edge: edge,
        );
  }

  void _updateResize(Offset globalPosition) {
    // Copied out of `widget`, matching `_start` above: resize never crosses
    // days, but resolving against the date's own grid still needs these
    // read fresh rather than closed over stale state.
    final date = widget.date;
    final settings = widget.settings;
    final slotHeight = widget.slotHeight;

    final renderObject = scheduleGridKeyFor(widget.column).currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final gridTop = renderObject.localToGlobal(Offset.zero).dy;
    // Clamps to the day's exact start/end rather than `slotStartForOffset`'s
    // null-outside-the-grid behavior (meant for where a *new* block can
    // start) — a resize's dragged edge should be able to reach the day's
    // real boundary instead of stopping one 15-minute slot short of it.
    final candidate = resizeCandidateForOffset(
      day: date,
      dy: globalPosition.dy - gridTop,
      settings: settings,
      slotHeight: slotHeight,
    );
    ref.read(resizeStateProvider.notifier).update(candidate);
  }

  void _endResize() {
    unawaited(ref.read(resizeStateProvider.notifier).commit());
  }

  void _cancelResize() {
    ref.read(resizeStateProvider.notifier).cancel();
  }

  @override
  Widget build(BuildContext context) {
    // `DayGrid` gives this widget's own outer `Positioned` extra size equal
    // to `widget.topBleed`/`widget.bottomBleed` on each side (see their
    // docs), so every position computed below is relative to *that*
    // enlarged box — the true block edges sit at local y = `topBleed` (top)
    // and `topBleed + blockHeight` (bottom), not at 0 and
    // `constraints.maxHeight`.
    return LayoutBuilder(
      builder: (context, constraints) {
        final topBleed = widget.topBleed;
        final bottomBleed = widget.bottomBleed;
        final blockHeight = constraints.maxHeight - topBleed - bottomBleed;

        final content = widget.block.locked
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismissDraft,
                child: widget.child,
              )
            : Listener(
                onPointerDown: (event) => _pointer = event.pointer,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: {
                    TapGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          TapGestureRecognizer
                        >(
                          TapGestureRecognizer.new,
                          (recognizer) => recognizer.onTap = () {
                            widget.onDismissDraft();
                            widget.onOpenEdit(widget.block);
                          },
                        ),
                    PanGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          PanGestureRecognizer
                        >(
                          () => PanGestureRecognizer()
                            ..supportedDevices = {
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.trackpad,
                            },
                          (recognizer) {
                            recognizer.onStart = (details) {
                              _start(details.globalPosition);
                            };
                          },
                        ),
                  },
                  child: widget.child,
                ),
              );

        final moveLayer = Positioned(
          top: topBleed,
          left: 0,
          right: 0,
          height: blockHeight,
          child: content,
        );

        if (widget.block.locked) {
          // A locked block has no resize zones, but its own outer
          // `Positioned` is still bled (see `DayGrid`'s per-block loop) —
          // absorb the bleed margin here too rather than let it leak
          // through to `DayGrid`'s background detector underneath.
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(behavior: HitTestBehavior.opaque),
              ),
              moveLayer,
            ],
          );
        }

        final halfStrip = _mouseStripHeight / 2;
        final midpoint = blockHeight / 2;
        // Clamped to the true midpoint so the two mouse strips never
        // overlap each other even on a block shorter than the strip
        // height itself — in practice the app's minimum block (8px) is
        // already taller than `_mouseStripHeight`, so this rarely bites,
        // but it keeps the split correct regardless. Both are relative to
        // the block's own true top (local y = `topBleed`).
        final topStripBottom = halfStrip < midpoint ? halfStrip : midpoint;
        final bottomStripTop = (blockHeight - halfStrip) > midpoint
            ? blockHeight - halfStrip
            : midpoint;
        // How far each strip may actually overshoot past the block's true
        // edge, capped by whatever bleed this block was granted on that
        // side (see [resizeBleedForBlocks]) — a block right up against a
        // neighbor gets 0 here, and the strip simply sits flush with the
        // true edge instead of bleeding outward.
        final topOvershoot = halfStrip < topBleed ? halfStrip : topBleed;
        final bottomOvershoot = halfStrip < bottomBleed
            ? halfStrip
            : bottomBleed;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Opaque catch-all filling the whole enlarged (bled) box,
            // beneath every other layer here. The touch zone and mouse
            // strips above are deliberately `translucent` so their own
            // recognizers can coexist with the move layer — but
            // `translucent` never claims a definitive hit, so without this
            // a pointer landing only within the bleed margin (outside
            // `moveLayer`'s true bounds, e.g. right on a mouse resize
            // strip) would fall all the way through this block to
            // `DayGrid`'s own background detector underneath, double-
            // registering recognizers there too.
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.opaque),
            ),
            moveLayer,
            // Touch: a single shared zone where a move (long-press) and a
            // resize (immediate vertical drag) race in the same gesture
            // arena — holding still favors the long-press timer, a quick
            // drag favors the drag recognizer's slop-exceeded acceptance.
            // `translucent` lets the mouse `PanGestureRecognizer` above
            // keep receiving events underneath this zone too. Fills the
            // whole enlarged box exactly, since its bleed is already
            // baked into that box's own size.
            Positioned.fill(
              key: const Key('day-grid-touch-resize-zone'),
              child: RawGestureDetector(
                behavior: HitTestBehavior.translucent,
                gestures: {
                  LongPressGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer
                      >(
                        () =>
                            LongPressGestureRecognizer()
                              ..supportedDevices = {PointerDeviceKind.touch},
                        (recognizer) {
                          recognizer.onLongPressStart = (details) {
                            _start(details.globalPosition);
                          };
                        },
                      ),
                  VerticalDragGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        VerticalDragGestureRecognizer
                      >(
                        () =>
                            VerticalDragGestureRecognizer()
                              ..supportedDevices = {PointerDeviceKind.touch},
                        (recognizer) {
                          recognizer.onStart = (details) {
                            final edge = resizeEdgeForLocalY(
                              localY: details.localPosition.dy - topBleed,
                              blockHeight: blockHeight,
                            );
                            _startResize(edge);
                            // The arena can resolve mid-gesture rather than
                            // at pointer-down when racing against
                            // `LongPressGestureRecognizer` (see the class
                            // docs on the touch zone above), in which case
                            // `onStart` already carries the full movement
                            // and no `onUpdate` ever follows for a single
                            // quick drag. Applying the position here too
                            // keeps both cases correct.
                            _updateResize(details.globalPosition);
                          };
                          recognizer.onUpdate = (details) =>
                              _updateResize(details.globalPosition);
                          recognizer.onEnd = (_) => _endResize();
                          recognizer.onCancel = _cancelResize;
                        },
                      ),
                },
              ),
            ),
            // Mouse: thin, precise strips right at the true edges —
            // "classic" desktop resize handles, with a resize cursor shown
            // on hover. `translucent` so a mouse pointer that lands
            // outside both strips (most of a tiny block) still reaches the
            // move `PanGestureRecognizer` above.
            Positioned(
              key: const Key('day-grid-resize-start-handle'),
              top: topBleed - topOvershoot,
              left: 0,
              right: 0,
              height: topOvershoot + topStripBottom,
              child: MouseRegion(
                // `MouseRegion` defaults to `opaque: true`, which would
                // absorb hit-testing at this point regardless of the
                // translucent `RawGestureDetector` beneath it — blocking
                // the touch race zone and the move detector further down
                // the Stack whenever a non-mouse pointer, or a mouse
                // pointer outside this strip's own recognizer, lands here.
                opaque: false,
                cursor: SystemMouseCursors.resizeRow,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  gestures: {
                    VerticalDragGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          VerticalDragGestureRecognizer
                        >(
                          () => VerticalDragGestureRecognizer()
                            ..supportedDevices = {
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.trackpad,
                            },
                          (recognizer) {
                            recognizer.onStart = (details) {
                              _startResize(ResizeEdge.start);
                              // See the touch zone's matching comment: the
                              // arena can resolve mid-gesture, in which
                              // case `onStart` already carries the full
                              // movement and no `onUpdate` follows.
                              _updateResize(details.globalPosition);
                            };
                            recognizer.onUpdate = (details) =>
                                _updateResize(details.globalPosition);
                            recognizer.onEnd = (_) => _endResize();
                            recognizer.onCancel = _cancelResize;
                          },
                        ),
                  },
                ),
              ),
            ),
            Positioned(
              key: const Key('day-grid-resize-end-handle'),
              top: topBleed + bottomStripTop,
              left: 0,
              right: 0,
              height: (blockHeight + bottomOvershoot) - bottomStripTop,
              child: MouseRegion(
                // `MouseRegion` defaults to `opaque: true`, which would
                // absorb hit-testing at this point regardless of the
                // translucent `RawGestureDetector` beneath it — blocking
                // the touch race zone and the move detector further down
                // the Stack whenever a non-mouse pointer, or a mouse
                // pointer outside this strip's own recognizer, lands here.
                opaque: false,
                cursor: SystemMouseCursors.resizeRow,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  gestures: {
                    VerticalDragGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          VerticalDragGestureRecognizer
                        >(
                          () => VerticalDragGestureRecognizer()
                            ..supportedDevices = {
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.trackpad,
                            },
                          (recognizer) {
                            recognizer.onStart = (details) {
                              _startResize(ResizeEdge.end);
                              // See the touch zone's matching comment: the
                              // arena can resolve mid-gesture, in which
                              // case `onStart` already carries the full
                              // movement and no `onUpdate` follows.
                              _updateResize(details.globalPosition);
                            };
                            recognizer.onUpdate = (details) =>
                                _updateResize(details.globalPosition);
                            recognizer.onEnd = (_) => _endResize();
                            recognizer.onCancel = _cancelResize;
                          },
                        ),
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The draft prompt shown while placing a new block: a plain gray,
/// dashed-outline box sized to the block's real duration, with two
/// fixed-size icon buttons centered on it, one per kind of block it can
/// create.
///
/// The buttons stay full-size even when the box itself (a 15-minute slot,
/// say) is too short to contain them — they overflow past its edges rather
/// than shrinking or being clipped.
class _DraftOverlay extends StatelessWidget {
  const new({required this.onCreateEvent, required this.onCreateFrame});

  final VoidCallback onCreateEvent;
  final VoidCallback onCreateFrame;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: const _DashedBorderPainter(color: Colors.grey),
            child: ColoredBox(color: Colors.grey.withValues(alpha: 0.2)),
          ),
        ),
        Center(
          child: OverflowBox(
            minHeight: 0,
            maxHeight: double.infinity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DraftButton(
                  color: BlockKind.frame.color,
                  icon: BlockKind.frame.icon,
                  label: 'Create Frame',
                  onTap: onCreateFrame,
                ),
                const SizedBox(width: 8),
                _DraftButton(
                  color: BlockKind.anchor.color,
                  icon: BlockKind.anchor.icon,
                  label: 'Create Event',
                  onTap: onCreateEvent,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One fixed-size, colored icon button on the [_DraftOverlay].
class _DraftButton extends StatelessWidget {
  const new({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  static const double _size = 28;

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: _size,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Center(child: Icon(icon, color: Colors.white, size: 16)),
          ),
        ),
      ),
    );
  }
}

/// Paints a dashed rectangle outline around its bounds.
class _DashedBorderPainter extends CustomPainter {
  const new({required this.color});

  final Color color;

  static const double _dashWidth = 4;
  static const double _dashGap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final outline = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DayGridPainter extends CustomPainter {
  const new({
    required this.settings,
    required this.slotHeight,
    required this.lineColor,
    required this.labelStyle,
    required this.gridLeft,
    required this.showLabels,
  });

  final DaySettings settings;
  final double slotHeight;
  final Color lineColor;
  final TextStyle? labelStyle;
  final double gridLeft;
  final bool showLabels;

  static const double _labelLeft = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final hourPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5;
    final quarterPaint = Paint()
      ..color = lineColor.withValues(alpha: lineColor.a * 0.5)
      ..strokeWidth = 1;

    final totalHours = settings.dayEndHour - settings.dayStartHour;
    for (var hour = 0; hour <= totalHours; hour++) {
      final y = hour * 4 * slotHeight;
      canvas.drawLine(Offset(gridLeft, y), Offset(size.width, y), hourPaint);

      if (hour < totalHours) {
        for (var quarter = 1; quarter < 4; quarter++) {
          final qy = y + quarter * slotHeight;
          canvas.drawLine(
            Offset(gridLeft, qy),
            Offset(size.width, qy),
            quarterPaint,
          );
        }
      }

      if (!showLabels) continue;

      final labelHour = settings.dayStartHour + hour;
      if (labelHour.isEven) {
        final painter = TextPainter(
          text: TextSpan(
            text: '${labelHour.toString().padLeft(2, '0')}:00',
            style: labelStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelY = (y - painter.height / 2).clamp(
          0.0,
          size.height - painter.height,
        );
        painter.paint(canvas, Offset(_labelLeft, labelY));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DayGridPainter oldDelegate) =>
      oldDelegate.settings != settings ||
      oldDelegate.slotHeight != slotHeight ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.gridLeft != gridLeft ||
      oldDelegate.showLabels != showLabels;
}

/// Draws the current-time marker line above the blocks, so it stays visible
/// even where a block's opaque background would otherwise hide it.
class _NowLinePainter extends CustomPainter {
  const new({required this.y});

  final double y;

  static const Color _color = Color(0xFF8B0000);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _color
      ..strokeWidth = 2;
    canvas
      ..drawLine(Offset(0, y), Offset(size.width, y), paint)
      ..drawCircle(Offset(0, y), 3, paint);
  }

  @override
  bool shouldRepaint(covariant _NowLinePainter oldDelegate) =>
      oldDelegate.y != y;
}
