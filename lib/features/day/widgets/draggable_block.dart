import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/drag_state_provider.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/resize_state_provider.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';

/// Wraps one rendered block with the gestures that *start* a drag: a
/// long-press on touch, an immediate pan on mouse/trackpad, and a plain tap
/// (forwarded to `onDismissDraft`) on any device. Locked blocks only get
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
/// Each block's own `DraggableBlock` gets an opaque catch-all covering its
/// *entire* bled box (see that class's docs), so an unclamped bleed would
/// let one block's hit region silently steal pointer events meant for a
/// neighbor sitting right next to it — most visible in a densely-packed
/// part of the day, where many blocks are back-to-back or nearly so.
/// [blocks] need not be pre-sorted; this sorts its own copy by `start` to
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

/// Wraps one rendered block with the gestures that start a move or resize —
/// see the docs above [resizeEdgeForLocalY] and [resizeBleedForBlocks] for
/// the design this widget implements.
class DraggableBlock extends ConsumerStatefulWidget {
  /// Creates a [DraggableBlock] wrapping [child] with the gestures that
  /// start a move or resize of [block].
  const new({
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
    super.key,
  });

  /// The block this widget wraps.
  final TimeObject block;

  /// This block's column identity — used as the drag/resize origin.
  final ScheduleColumn column;

  /// Reads/moves this column's blocks during a drag or resize.
  final ScheduleController controller;

  /// The date this block's column shows, used to resolve resize positions.
  final DateTime date;

  /// The grid's visible start/end hours.
  final DaySettings settings;

  /// Pixel height of a single 15-minute slot.
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

  /// Called to dismiss the in-progress draft, if any, e.g. on a tap that
  /// starts neither a move nor a resize.
  final VoidCallback onDismissDraft;

  /// Called to open the block-edit modal for [block].
  final void Function(TimeObject block) onOpenEdit;

  /// The block's own rendered content.
  final Widget child;

  /// The maximum either of [topBleed]/[bottomBleed] may ever be, used by
  /// `DayGrid` as the upper bound passed to [resizeBleedForBlocks].
  static const double hitBleed = 9;

  @override
  ConsumerState<DraggableBlock> createState() => _DraggableBlockState();
}

class _DraggableBlockState extends ConsumerState<DraggableBlock> {
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

        const halfStrip = _mouseStripHeight / 2;
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
                          recognizer
                            ..onStart = (details) {
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
                            }
                            ..onUpdate = (details) {
                              _updateResize(details.globalPosition);
                            }
                            ..onEnd = (_) {
                              _endResize();
                            }
                            ..onCancel = _cancelResize;
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
            _ResizeHandle(
              resizeKey: const Key('day-grid-resize-start-handle'),
              top: topBleed - topOvershoot,
              height: topOvershoot + topStripBottom,
              edge: ResizeEdge.start,
              onStart: (edge, position) {
                _startResize(edge);
                _updateResize(position);
              },
              onUpdate: _updateResize,
              onEnd: _endResize,
              onCancel: _cancelResize,
            ),
            _ResizeHandle(
              resizeKey: const Key('day-grid-resize-end-handle'),
              top: topBleed + bottomStripTop,
              height: (blockHeight + bottomOvershoot) - bottomStripTop,
              edge: ResizeEdge.end,
              onStart: (edge, position) {
                _startResize(edge);
                _updateResize(position);
              },
              onUpdate: _updateResize,
              onEnd: _endResize,
              onCancel: _cancelResize,
            ),
          ],
        );
      },
    );
  }
}

/// One mouse resize strip — the thin, precise handle sitting at a
/// block's true top or bottom edge (see [_DraggableBlockState.build]'s
/// "classic" desktop resize handles comment). Identical for the start
/// and end edges except for [edge], geometry, and which
/// [_DraggableBlockState] callback each drag stage invokes.
class _ResizeHandle extends StatelessWidget {
  const new({
    required this.resizeKey,
    required this.top,
    required this.height,
    required this.edge,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final Key resizeKey;
  final double top;
  final double height;
  final ResizeEdge edge;

  /// Called on drag start with [edge] and the pointer's global position —
  /// the caller both starts the resize for [edge] and immediately applies
  /// this first position, matching the original two call sites' comment
  /// about the arena resolving mid-gesture.
  final void Function(ResizeEdge edge, Offset globalPosition) onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: resizeKey,
      top: top,
      left: 0,
      right: 0,
      height: height,
      child: MouseRegion(
        // See the original handles' comment: `opaque: false` so a pointer
        // outside this strip's own recognizer still reaches the touch
        // race zone and move detector beneath it.
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
                    recognizer
                      ..onStart = (details) {
                        onStart(edge, details.globalPosition);
                      }
                      ..onUpdate = (details) {
                        onUpdate(details.globalPosition);
                      }
                      ..onEnd = (_) {
                        onEnd();
                      }
                      ..onCancel = onCancel;
                  },
                ),
          },
        ),
      ),
    );
  }
}
