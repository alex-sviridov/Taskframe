import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/schedule_controller.dart';

/// Resolves a global pointer position into the column and 15-minute slot
/// under it, or `null` when the pointer is over no column.
///
/// Supplied by the widget that starts a drag (it knows the grid's
/// settings and slot height) and then called by [DragNotifier] for the
/// rest of the drag's life, so target resolution keeps working after that
/// widget is gone.
typedef DragTargetResolver =
    ({ScheduleColumn column, DateTime start})? Function(Offset globalPosition);

/// Tracks the block currently being dragged to a new time/date, if any.
///
/// `null` when no drag is in progress. Read by any visible `DayGrid`
/// column to render the landzone shadow, and by `DayScreen` to drive
/// edge-triggered day/week paging.
///
/// ## Pointer ownership
///
/// Once a drag starts, this notifier — not the dragged block's widget —
/// owns the pointer for the rest of the gesture, via a *global route* on
/// [GestureBinding]'s [PointerRouter]. That matters because edge-triggered
/// paging can turn the page mid-drag, which unmounts the origin page's
/// element subtree; unmounting disposes its `GestureRecognizer`s, and
/// `OneSequenceGestureRecognizer.dispose()` removes the pointer's route, so
/// the widget-local recognizer would silently stop receiving move events
/// *and never fire its end/cancel callbacks either* — leaving the drag
/// state stuck non-null forever, the block permanently hidden, and the
/// edge-dwell timer re-arming itself indefinitely.
///
/// A global route is registered on the router singleton rather than on any
/// `Element`/`State`/`RenderObject`, so it keeps receiving every event for
/// its pointer no matter what mounts or unmounts in the meantime. The
/// widget-local recognizers therefore only detect the *start* of a drag;
/// all update/end/cancel handling happens here.
class DragNotifier extends Notifier<DragState?> {
  /// The pointer id this notifier currently owns a global route for.
  int? _pointer;

  /// The registered global route, kept so it can be removed again — a
  /// leaked route would misfire on the next gesture that recycles the same
  /// pointer id.
  PointerRoute? _globalRoute;

  DragTargetResolver? _resolveTarget;

  /// The controller every read/move of the in-flight drag goes through,
  /// matching [DragState.originalColumn]'s variant. Set by [start].
  ScheduleController? _controller;

  @override
  DragState? build() {
    ref.onDispose(_releasePointer);
    return null;
  }

  /// Begins dragging [block], which belonged to [originalColumn]. The
  /// landzone starts at the block's own current column/time. [controller]
  /// is used for every subsequent read/move this drag makes, so it must
  /// match [originalColumn]'s kind (a `DayScheduleController` for a
  /// [DayColumn], and so on).
  void start({
    required TimeObject block,
    required ScheduleColumn originalColumn,
    required ScheduleController controller,
    required Offset pointerGlobalPosition,
    int? pointer,
    DragTargetResolver? resolveTarget,
  }) {
    state = DragState(
      block: block,
      originalColumn: originalColumn,
      targetColumn: originalColumn,
      targetStart: block.start,
      pointerGlobalPosition: pointerGlobalPosition,
    );
    _takePointer(pointer, resolveTarget);
    // After [_takePointer], not before: it releases any previous gesture
    // first, and that teardown clears [_controller] along with the rest.
    _controller = controller;
  }

  /// Updates the dragging pointer's position and its landzone.
  ///
  /// [targetColumn]/[targetStart] are the freshly resolved target under
  /// the pointer; passing `null` for them means the pointer is over no
  /// column right now, which *clears* the landzone rather than leaving a
  /// stale one showing. That keeps what the user sees honest: releasing
  /// where no landzone is drawn cancels the move. Does nothing if no drag
  /// is in progress.
  void updatePointer(
    Offset globalPosition, {
    ScheduleColumn? targetColumn,
    DateTime? targetStart,
  }) {
    final current = state;
    if (current == null) return;
    var resolvedColumn = targetColumn;
    var resolvedStart = targetStart;
    if (resolvedColumn != null &&
        resolvedStart != null &&
        _overlapsExisting(current.block, resolvedColumn, resolvedStart)) {
      resolvedColumn = current.originalColumn;
      resolvedStart = current.block.start;
    }
    state = current.copyWith(
      targetColumn: resolvedColumn,
      targetStart: resolvedStart,
      pointerGlobalPosition: globalPosition,
      clearTarget: resolvedColumn == null || resolvedStart == null,
    );
  }

  /// Whether placing [dragged] at [column]/[start] would overlap another
  /// block already on [column].
  bool _overlapsExisting(
    TimeObject dragged,
    ScheduleColumn column,
    DateTime start,
  ) {
    final blocks = _controller?.blocksOf(ref, column);
    if (blocks == null) return false;
    final end = start.add(dragged.end.difference(dragged.start));
    return blocks.any(
      (block) => block.id != dragged.id && block.overlaps(start, end),
    );
  }

  /// Commits the current drag: moves the block to its current landzone
  /// column/time via [_controller], then clears the drag. Does nothing if
  /// no drag is in progress; cancels instead if there is no valid
  /// landzone.
  Future<void> drop() async {
    final current = state;
    if (current == null) return;
    final toColumn = current.targetColumn;
    final newStart = current.targetStart;
    if (toColumn == null || newStart == null) {
      cancel();
      return;
    }
    final controller = _controller!;
    // TODO(alex): clearing the drag state before awaiting `moveBlock` means
    // a failing move would surface as an unhandled async error and a
    // silent UI no-op (the block snaps back with no explanation). Fine for
    // today's in-memory stubs, which cannot fail; must be revisited before
    // any real or networked repository backs this.
    state = null;
    _releasePointer();

    final duration = current.block.end.difference(current.block.start);
    await controller.moveBlock(
      ref,
      block: current.block,
      fromColumn: current.originalColumn,
      toColumn: toColumn,
      newStart: newStart,
      newEnd: newStart.add(duration),
    );
  }

  /// Abandons the current drag without moving the block.
  void cancel() {
    state = null;
    _releasePointer();
  }

  /// Registers a global pointer route for [pointer], replacing any route
  /// this notifier already held.
  void _takePointer(int? pointer, DragTargetResolver? resolveTarget) {
    _releasePointer();
    if (pointer == null) return;
    _pointer = pointer;
    _resolveTarget = resolveTarget;
    final route = _handlePointerEvent;
    _globalRoute = route;
    GestureBinding.instance.pointerRouter.addGlobalRoute(route);
  }

  /// Removes the global route, if any, and drops everything that belonged
  /// to the finished gesture. Safe to call repeatedly, and never touches
  /// [GestureBinding] unless a route was actually registered (so
  /// binding-free unit tests can use this notifier).
  ///
  /// Removing the route is the part that matters: a leaked route would
  /// misfire on the next gesture that recycles the same pointer id.
  void _releasePointer() {
    final route = _globalRoute;
    if (route != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(route);
    }
    _globalRoute = null;
    _pointer = null;
    _resolveTarget = null;
    _controller = null;
  }

  /// Drives the whole in-flight drag from raw pointer events, independent
  /// of whether the block's own widget is still mounted.
  void _handlePointerEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    final current = state;
    if (current == null) {
      _releasePointer();
      return;
    }

    if (event is PointerMoveEvent) {
      final target = _resolveTarget?.call(event.position);
      updatePointer(
        event.position,
        targetColumn: target?.column ?? current.originalColumn,
        targetStart: target?.start ?? current.block.start,
      );
    } else if (event is PointerUpEvent) {
      final target = _resolveTarget?.call(event.position);
      if (target == null) {
        cancel();
      } else {
        updatePointer(
          event.position,
          targetColumn: target.column,
          targetStart: target.start,
        );
        unawaited(drop());
      }
    } else if (event is PointerCancelEvent) {
      cancel();
    }
  }
}

/// The block currently being dragged to a new time/date, if any.
final dragStateProvider = NotifierProvider<DragNotifier, DragState?>(
  DragNotifier.new,
);

/// Projects [dragState] to the value a `DayGrid` for [column] actually
/// cares about, collapsing to `null` whenever [column] is neither the
/// drag's origin nor its current landzone target.
DragState? dragStateForColumn(DragState? dragState, ScheduleColumn column) {
  if (dragState == null) return null;
  final relevant =
      dragState.originalColumn == column || dragState.targetColumn == column;
  return relevant ? dragState : null;
}
