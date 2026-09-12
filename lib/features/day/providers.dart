import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/schedule_controller.dart';
import 'package:taskframe/features/day/template_apply.dart';
import 'package:taskframe/features/template/providers.dart';

/// The shortest duration a block can be resized down to.
const _minBlockDuration = Duration(minutes: 15);

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Holds the date currently shown on the day screen, normalized to
/// midnight.
class SelectedDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => _today();

  /// The selected date. Settable directly so the day view can follow its
  /// own swipe/page navigation.
  DateTime get date => state;
  set date(DateTime value) => state = value;
}

/// The date currently shown on the day screen.
final selectedDateProvider = NotifierProvider<SelectedDateNotifier, DateTime>(
  SelectedDateNotifier.new,
);

/// The backing store for day blocks.
///
/// Overriding this single provider (e.g. with an API-backed
/// [DayBlocksRepository]) is enough to change where blocks are loaded from
/// and saved to; nothing downstream needs to change.
final dayBlocksRepositoryProvider = Provider<DayBlocksRepository>(
  (ref) => InMemoryDayBlocksRepository(),
);

/// Holds the timeline blocks for one date, loaded from
/// [dayBlocksRepositoryProvider], and lets the day screen add new ones.
class DayBlocksNotifier extends AsyncNotifier<List<TimeObject>> {
  /// Creates a [DayBlocksNotifier] for [date].
  new(this.date);

  /// The date this notifier's blocks belong to.
  final DateTime date;

  @override
  Future<List<TimeObject>> build() =>
      ref.watch(dayBlocksRepositoryProvider).load(date);

  /// Creates a new block on [date], adds it to the current state, and
  /// returns it.
  Future<TimeObject> addBlock({
    required DateTime start,
    required DateTime end,
    required BlockKind kind,
    String? title,
    String? categoryId,
  }) async {
    final repository = ref.read(dayBlocksRepositoryProvider);
    final added = await repository.add(
      date,
      start: start,
      end: end,
      kind: kind,
      title: title,
      categoryId: categoryId,
    );
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Updates [block]'s title/start/end/kind, persisting via the repository
  /// and refreshing state. Silently does nothing if the resulting start/end
  /// would be invalid (see [isValidBlockEdit]) — title/kind-only edits are
  /// always valid since they don't touch start/end.
  Future<void> updateBlock(
    TimeObject block, {
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    String? categoryId,
  }) async {
    final newStart = start ?? block.start;
    final newEnd = end ?? block.end;
    final others = (state.value ?? []).where((b) => b.id != block.id).toList();
    final settings = ref.read(daySettingsProvider);
    if (!isValidBlockEdit(
      start: newStart,
      end: newEnd,
      settings: settings,
      day: date,
      others: others,
    )) {
      return;
    }

    final repository = ref.read(dayBlocksRepositoryProvider);
    final updated = await repository.update(
      block,
      date: date,
      title: title,
      start: start,
      end: end,
      kind: kind,
      categoryId: categoryId,
    );
    state = AsyncData([
      for (final b in state.value ?? <TimeObject>[])
        if (b.id == block.id) updated else b,
    ]);
  }

  /// Removes [block], persisting via the repository and refreshing state.
  Future<void> deleteBlock(TimeObject block) async {
    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.delete(block, date: date);
    state = AsyncData([
      for (final b in state.value ?? <TimeObject>[])
        if (b.id != block.id) b,
    ]);
  }

  /// Adds a copy of [block] (same title/kind/duration, same time of day) to
  /// the following date's blocks.
  Future<void> copyToNextDay(TimeObject block) async {
    final nextDate = DateTime(date.year, date.month, date.day + 1);
    final duration = block.end.difference(block.start);
    final nextStart = DateTime(
      nextDate.year,
      nextDate.month,
      nextDate.day,
      block.start.hour,
      block.start.minute,
    );
    await ref
        .read(dayBlocksProvider(nextDate).notifier)
        .addBlock(
          start: nextStart,
          end: nextStart.add(duration),
          kind: block.kind,
          title: block.title,
          categoryId: block.categoryId,
        );
  }

  /// Applies [templateId]'s blocks to [date]: each is rebased onto this
  /// day's time-of-day and added unless it overlaps an existing block (or
  /// another template block already accepted in this same apply), per
  /// [resolveTemplateApply]. Partial — a conflicting block is skipped
  /// rather than aborting the whole apply.
  Future<TemplateApplyResult> applyTemplate(String templateId) async {
    final templateBlocks = await ref.read(
      templateBlocksProvider(templateId).future,
    );
    final resolved = resolveTemplateApply(
      templateBlocks: templateBlocks,
      dayBlocks: state.value ?? [],
      date: date,
    );

    final addedIds = <String>[];
    for (final block in resolved.toAdd) {
      final created = await addBlock(
        start: block.start,
        end: block.end,
        kind: block.kind,
        title: block.title,
        categoryId: block.categoryId,
      );
      addedIds.add(created.id);
    }

    return (addedIds: addedIds, skipped: resolved.skipped);
  }
}

/// The timeline blocks for a given date.
// ignore: specify_nonobvious_property_types
final dayBlocksProvider =
    AsyncNotifierProvider.family<DayBlocksNotifier, List<TimeObject>, DateTime>(
      DayBlocksNotifier.new,
    );

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

/// Tracks the block currently being resized by dragging one of its edges,
/// if any.
///
/// `null` when no resize is in progress. A resize never changes a block's
/// date, so unlike [DragNotifier] this needs no pointer-ownership dance —
/// the widget driving the drag stays mounted for its whole lifetime.
class ResizeNotifier extends Notifier<ResizeState?> {
  ScheduleController? _controller;

  @override
  ResizeState? build() => null;

  /// Begins resizing [block] on [column] from [edge]. The draft starts out
  /// equal to the block's own current start/end. [controller] is used for
  /// every subsequent read/commit this resize makes.
  void start({
    required TimeObject block,
    required ScheduleColumn column,
    required ScheduleController controller,
    required ResizeEdge edge,
  }) {
    _controller = controller;
    state = ResizeState(
      block: block,
      column: column,
      edge: edge,
      draftStart: block.start,
      draftEnd: block.end,
    );
  }

  /// Updates the dragged edge's draft time to [candidate] (already
  /// snapped to the 15-minute grid), clamped so the block never shrinks
  /// below [_minBlockDuration] and never overlaps another block on
  /// [ResizeState.column].
  void update(DateTime candidate) {
    final current = state;
    if (current == null) return;
    final others = (_controller?.blocksOf(ref, current.column) ?? []).where(
      (block) => block.id != current.block.id,
    );

    if (current.edge == ResizeEdge.end) {
      var newEnd = candidate;
      final minEnd = current.draftStart.add(_minBlockDuration);
      if (newEnd.isBefore(minEnd)) newEnd = minEnd;
      for (final block in others) {
        if (block.start.isAfter(current.draftStart) &&
            block.start.isBefore(newEnd)) {
          newEnd = block.start;
        }
      }
      state = current.copyWith(draftEnd: newEnd);
    } else {
      var newStart = candidate;
      final maxStart = current.draftEnd.subtract(_minBlockDuration);
      if (newStart.isAfter(maxStart)) newStart = maxStart;
      for (final block in others) {
        if (block.end.isBefore(current.draftEnd) &&
            block.end.isAfter(newStart)) {
          newStart = block.end;
        }
      }
      state = current.copyWith(draftStart: newStart);
    }
  }

  /// Commits the current resize: persists the draft start/end via
  /// [_controller], then clears the resize. Does nothing if no resize is
  /// in progress.
  Future<void> commit() async {
    final current = state;
    if (current == null) return;
    final controller = _controller!;
    state = null;

    await controller.moveBlock(
      ref,
      block: current.block,
      fromColumn: current.column,
      toColumn: current.column,
      newStart: current.draftStart,
      newEnd: current.draftEnd,
    );
  }

  /// Abandons the current resize without changing the block.
  void cancel() {
    state = null;
  }
}

/// The block currently being resized, if any.
final resizeStateProvider = NotifierProvider<ResizeNotifier, ResizeState?>(
  ResizeNotifier.new,
);

/// Projects [resizeState] to the value a `DayGrid` for [column] actually
/// cares about, collapsing to `null` whenever the resize belongs to some
/// other column. See [dragStateForColumn], its drag equivalent.
ResizeState? resizeStateForColumn(
  ResizeState? resizeState,
  ScheduleColumn column,
) {
  if (resizeState == null) return null;
  return resizeState.column == column ? resizeState : null;
}
