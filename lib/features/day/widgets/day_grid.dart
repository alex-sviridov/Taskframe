import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/draft_state_provider.dart';
import 'package:taskframe/features/day/drag_state_provider.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/resize_state_provider.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
import 'package:taskframe/features/day/template_apply_effects.dart';
import 'package:taskframe/features/day/week_utils.dart';
import 'package:taskframe/features/day/widgets/block_edit_modal.dart';
import 'package:taskframe/features/day/widgets/block_view.dart';
import 'package:taskframe/features/day/widgets/day_grid_painters.dart';
import 'package:taskframe/features/day/widgets/draft_overlay.dart';
import 'package:taskframe/features/day/widgets/draggable_block.dart';
import 'package:taskframe/features/day/widgets/schedule_block_actions.dart';
import 'package:taskframe/features/day/widgets/template_apply_visuals.dart';

/// The 15-minute-aligned timeline: an hour grid with [blocks] drawn on top.
///
/// Clicking (desktop) or long-pressing (touch) free grid space opens a
/// draft for a new block there, sized to a default 30 minutes; dragging
/// vertically before releasing (mouse) or moving while still pressed
/// (touch) resizes the draft to span the drag instead. Tapping one of
/// [DraftOverlay]'s two icon buttons creates it via [onCreateBlock];
/// clicking elsewhere on the grid opens a new draft there, replacing it.
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
  /// The fixed point a draft-creating drag began at, set by [_openDraftAt]
  /// and read by [_updateDraftDrag] to resolve the draft's other edge as the
  /// pointer moves — the draft itself may end up starting before or after
  /// this point depending on which way the drag goes. Local rather than
  /// shared via `draftStateProvider`: a drag never leaves the column it
  /// started in, so nothing outside this widget ever needs it.
  DateTime? _draftAnchor;

  /// Whether a mouse drag is actively sizing a new draft right now (between
  /// the vertical-drag recognizer's start and its end/cancel) — drives the
  /// resize cursor shown over the grid background. Desktop-only: touch has
  /// no cursor to change.
  bool _isDragSizingDraft = false;

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

  /// Redraws once a minute while `widget.date` is today, so the
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

    // A frame marks where attention goes rather than a named activity, so
    // its title (kept internally so it survives a round-trip transform to
    // an anchor and back — see `BlockEditModal`) is never shown here.
    final showTitle = block.kind != BlockKind.frame;

    return Positioned(
      key: key,
      top: boxTop,
      left: _gridLeft,
      right: 0,
      height: _titleOverlayHeight,
      child: IgnorePointer(
        child: !showTitle
            ? const SizedBox.shrink()
            : Padding(
                // A tall block keeps its title hugging the top-left corner
                // (minimal top inset); a too-short block's box is already
                // centered on the block above, so its text is centered
                // within that box too rather than hugging its own top.
                padding: EdgeInsets.only(
                  left: 6,
                  right: 6,
                  top: isShort ? 0 : 1,
                ),
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

  /// The landzone/resize-draft preview box for [block] spanning
  /// `[start, end)`: a dashed, non-interactive outline around a
  /// surface-colored [BlockView], used by both the drag landzone and the
  /// resize draft — the two places `DayGrid` shows a block "as it would
  /// be" rather than as it currently is. Returns the box alongside its
  /// own top/height so the caller's matching [_titleOverlay] call reuses
  /// them instead of recomputing [_offsetFor] a second time.
  ({Widget box, double top, double height}) _previewBox({
    required Key boxKey,
    required TimeObject block,
    required DateTime start,
    required DateTime end,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final top = _offsetFor(start);
    final height = _offsetFor(end) - top;
    final box = Positioned(
      key: boxKey,
      top: top,
      left: _gridLeft,
      right: 0,
      height: height,
      child: IgnorePointer(
        child: CustomPaint(
          painter: DashedBorderPainter(color: scheme.primary),
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
    );
    return (box: box, top: top, height: height);
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
    _draftAnchor = start;
    ref
        .read(draftStateProvider.notifier)
        .openAt(column: widget.column, start: start, end: start.add(duration));
  }

  /// Resizes the in-progress draft to span from [_draftAnchor] to the
  /// pointer's current position at [dy], called on every move of a
  /// draft-creating drag. Does nothing before [_openDraftAt] has set an
  /// anchor.
  void _updateDraftDrag(double dy) {
    final anchor = _draftAnchor;
    if (anchor == null) return;

    final candidate = resizeCandidateForOffset(
      day: widget.date,
      dy: dy,
      settings: widget.settings,
      slotHeight: widget.slotHeight,
    );
    final range = draftRangeForDrag(
      anchor: anchor,
      candidate: candidate,
      day: widget.date,
      settings: widget.settings,
    );
    ref
        .read(draftStateProvider.notifier)
        .updateRange(start: range.start, end: range.end);
  }

  void _dismissDraft() {
    _draftAnchor = null;
    ref.read(draftStateProvider.notifier).dismiss();
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
    final draft = ref.read(
      draftStateProvider.select(
        (state) => draftStateForColumn(state, widget.column),
      ),
    )!;
    widget.onCreateBlock(start: draft.start, end: draft.end, kind: kind);
    _draftAnchor = null;
    ref.read(draftStateProvider.notifier).dismiss();
  }

  /// Wraps [child] in the newly-applied-template border pulse when [block]
  /// is one of [DayGrid.highlightedBlockIds], otherwise returns it as-is.
  Widget _maybeHighlighted({required TimeObject block, required Widget child}) {
    if (!widget.highlightedBlockIds.contains(block.id)) return child;
    return TemplateHighlightPulse(
      key: Key('day-grid-highlight-${block.id}'),
      onDone: () => widget.onHighlightAnimationEnd?.call(block.id),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = _slotCount * widget.slotHeight;
    // Selected rather than watched outright: a plain `ref.watch` here would
    // rebuild every visible `DayGrid` column on every pointer move of a drag
    // or resize happening on some other day (most columns, in week view).
    // `dragStateForColumn`/`resizeStateForColumn`/`draftStateForColumn`
    // collapse to `null` for a column the in-flight gesture doesn't touch,
    // and `null == null`, so `select` skips the rebuild there entirely.
    final draftState = ref.watch(
      draftStateProvider.select(
        (state) => draftStateForColumn(state, widget.column),
      ),
    );
    final draft = draftState == null
        ? null
        : (start: draftState.start, end: draftState.end);
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
      maxBleed: DraggableBlock.hitBleed,
    );
    final landzonePreview = dragState != null && landzoneStart != null
        ? _previewBox(
            boxKey: const Key('day-grid-landzone'),
            block: dragState.block,
            start: landzoneStart,
            end: landzoneStart.add(
              dragState.block.end.difference(dragState.block.start),
            ),
          )
        : null;
    final resizeDraftPreview =
        resizeState != null && resizeState.column == widget.column
        ? _previewBox(
            boxKey: const Key('day-grid-resize-draft'),
            block: resizeState.block,
            start: resizeState.draftStart,
            end: resizeState.draftEnd,
          )
        : null;

    return MouseRegion(
      // Wraps the whole grid, not just the background layer, so the cursor
      // stays the resize cursor even when the pointer ends up hovering the
      // rendered draft-preview box itself — which has no cursor override
      // of its own — rather than the background behind it. That happens
      // routinely on an upward drag: the draft's box top is floor-snapped
      // to the grid, which puts it above (not below) the real,
      // not-yet-snapped pointer position, so the pointer sits inside the
      // box rather than clear of it.
      key: const Key('day-grid-background-cursor'),
      cursor: _isDragSizingDraft
          ? SystemMouseCursors.resizeRow
          : MouseCursor.defer,
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              // Only the background layer reacts to gestures: blocks (and
              // the draft overlay) are drawn above it in this Stack and,
              // being opaque, absorb touches that start on them before
              // they ever
              // reach this GestureDetector.
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: {
                  // Mouse/trackpad: a plain click opens a default-sized
                  // draft; if the same gesture moves enough to be claimed by
                  // the vertical recognizer below instead, this never fires.
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TapGestureRecognizer
                      >(
                        () => TapGestureRecognizer()
                          ..supportedDevices = {
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                          },
                        (recognizer) =>
                            recognizer.onTapUp = (details) =>
                                _openDraftAt(details.localPosition.dy),
                      ),
                  // Mouse/trackpad: opens the draft at the drag's start and
                  // resizes it live as the pointer moves vertically, sizing
                  // the eventual block to the drag instead of the default.
                  VerticalDragGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        VerticalDragGestureRecognizer
                      >(
                        () => VerticalDragGestureRecognizer()
                          ..supportedDevices = {
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                          }
                          // Anchors the draft to where the pointer actually
                          // went down, not (the default) where the arena
                          // resolved the drag after the initial move past
                          // slop — which would already be offset from the
                          // real anchor.
                          ..dragStartBehavior = DragStartBehavior.down,
                        (recognizer) {
                          recognizer
                            ..onStart = (details) {
                              setState(() => _isDragSizingDraft = true);
                              _openDraftAt(details.localPosition.dy);
                            }
                            ..onUpdate = (details) {
                              _updateDraftDrag(details.localPosition.dy);
                            }
                            ..onEnd = (_) {
                              setState(() => _isDragSizingDraft = false);
                            }
                            ..onCancel = () {
                              setState(() => _isDragSizingDraft = false);
                            };
                        },
                      ),
                  // Touch: a long-press opens the draft (a plain tap is left
                  // free for other uses, e.g. scrolling); moving while still
                  // pressed resizes it live, same as the mouse vertical drag.
                  LongPressGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer
                      >(
                        () =>
                            LongPressGestureRecognizer()
                              ..supportedDevices = {PointerDeviceKind.touch},
                        (recognizer) {
                          recognizer
                            ..onLongPressStart = (details) {
                              _openDraftAt(details.localPosition.dy);
                            }
                            ..onLongPressMoveUpdate = (details) {
                              _updateDraftDrag(details.localPosition.dy);
                            };
                        },
                      ),
                  // Only registered when day-switching is enabled (see
                  // onSwipeStart's docs) — an always-present recognizer here,
                  // even with null callbacks, would still claim every
                  // horizontal drag and keep it from reaching an ancestor
                  // gesture detector in a caller that disables swiping.
                  if (widget.onSwipeStart != null ||
                      widget.onSwipeUpdate != null ||
                      widget.onSwipeEnd != null ||
                      widget.onSwipeCancel != null)
                    HorizontalDragGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          HorizontalDragGestureRecognizer
                        >(HorizontalDragGestureRecognizer.new, (recognizer) {
                          recognizer
                            ..onStart = widget.onSwipeStart
                            ..onUpdate = widget.onSwipeUpdate
                            ..onEnd = widget.onSwipeEnd
                            ..onCancel = widget.onSwipeCancel;
                        }),
                },
                child: CustomPaint(
                  painter: DayGridPainter(
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
                // Enlarged by up to `DraggableBlock.hitBleed` on each
                // side — clamped per [resizeBleedForBlocks] so a
                // time-adjacent neighbor's true bounds are never intruded
                // on — giving the touch resize zone (and, on a very short
                // block, the mouse resize strips) room to bleed past the
                // block's true edges. Hit-testing gates on a render
                // object's own reported size, so that bleed only works if
                // it's baked in here rather than attempted via `Clip.none`
                // alone. `DraggableBlock` insets its real visual content
                // back to the true, unbled bounds.
                top:
                    _offsetFor(block.start) - (resizeBleed[block.id]?.top ?? 0),
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
                // still gives DraggableBlock's opaque detector a hit-test
                // region at the block's original rect for the duration of
                // the drag. Harmless in practice — the landzone painted over
                // it is IgnorePointer-wrapped, and a stray tap here only
                // no-ops through _dismissDraft.
                child: DraggableBlock(
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
                  child: DraftOverlay(
                    onCreateEvent: () => _create(BlockKind.anchor),
                    onCreateFrame: () => _create(BlockKind.frame),
                  ),
                ),
              ),
            if (landzonePreview != null) ...[
              landzonePreview.box,
              _titleOverlay(
                key: const Key('day-grid-landzone-title'),
                block: dragState!.block,
                trueTop: landzonePreview.top,
                trueHeight: landzonePreview.height,
              ),
            ],
            if (resizeDraftPreview != null) ...[
              resizeDraftPreview.box,
              _titleOverlay(
                key: const Key('day-grid-resize-draft-title'),
                block: resizeState!.block,
                trueTop: resizeDraftPreview.top,
                trueHeight: resizeDraftPreview.height,
              ),
            ],
            if (nowLineY != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: NowLinePainter(y: nowLineY)),
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
                  child: TemplateGhostOverlay(
                    onDone: () => widget.onGhostAnimationEnd?.call(ghost.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
