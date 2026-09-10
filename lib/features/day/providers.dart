import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/data/day_blocks_repository.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/drag_state.dart';
import 'package:taskframe/features/day/models/resize_state.dart';
import 'package:taskframe/features/day/models/time_object.dart';

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
  }) async {
    final repository = ref.read(dayBlocksRepositoryProvider);
    final added = await repository.add(
      date,
      start: start,
      end: end,
      kind: kind,
      title: title,
    );
    state = AsyncData([...?state.value, added]);
    return added;
  }

  /// Updates [block]'s title/start/end, persisting via the repository and
  /// refreshing state. Silently does nothing if the resulting start/end
  /// would be invalid (see [isValidBlockEdit]) — title-only edits are
  /// always valid since they don't touch start/end.
  Future<void> updateBlock(
    TimeObject block, {
    String? title,
    DateTime? start,
    DateTime? end,
  }) async {
    final newStart = start ?? block.start;
    final newEnd = end ?? block.end;
    final others = (state.value ?? [])
        .where((b) => b.id != block.id)
        .toList();
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
        );
  }
}

/// The timeline blocks for a given date.
// ignore: specify_nonobvious_property_types
final dayBlocksProvider =
    AsyncNotifierProvider.family<DayBlocksNotifier, List<TimeObject>, DateTime>(
      DayBlocksNotifier.new,
    );

/// Resolves a global pointer position into the day column and 15-minute
/// slot under it, or `null` when the pointer is over no column.
///
/// Supplied by the widget that starts a drag (it knows the grid's settings
/// and slot height) and then called by [DragNotifier] for the rest of the
/// drag's life, so target resolution keeps working after that widget is
/// gone.
typedef DragTargetResolver = ({DateTime date, DateTime start})? Function(
  Offset globalPosition,
);

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

  @override
  DragState? build() {
    ref.onDispose(_releasePointer);
    return null;
  }

  /// Begins dragging [block], which belonged to [originalDate]. The
  /// landzone starts at the block's own current date/time.
  ///
  /// When [pointer] is given, this notifier takes ownership of that
  /// pointer for the rest of the drag (see the class docs) and drives all
  /// further updates itself, resolving landzones with [resolveTarget].
  void start({
    required TimeObject block,
    required DateTime originalDate,
    required Offset pointerGlobalPosition,
    int? pointer,
    DragTargetResolver? resolveTarget,
  }) {
    state = DragState(
      block: block,
      originalDate: originalDate,
      targetDate: originalDate,
      targetStart: block.start,
      pointerGlobalPosition: pointerGlobalPosition,
    );
    _takePointer(pointer, resolveTarget);
  }

  /// Updates the dragging pointer's position and its landzone.
  ///
  /// [targetDate]/[targetStart] are the freshly resolved target under the
  /// pointer; passing `null` for them means the pointer is over no column
  /// right now, which *clears* the landzone rather than leaving a stale one
  /// showing. That keeps what the user sees honest: releasing where no
  /// landzone is drawn cancels the move. Does nothing if no drag is in
  /// progress.
  void updatePointer(
    Offset globalPosition, {
    DateTime? targetDate,
    DateTime? targetStart,
  }) {
    final current = state;
    if (current == null) return;
    var resolvedDate = targetDate;
    var resolvedStart = targetStart;
    if (resolvedDate != null &&
        resolvedStart != null &&
        _overlapsExisting(current.block, resolvedDate, resolvedStart)) {
      resolvedDate = current.originalDate;
      resolvedStart = current.block.start;
    }
    state = current.copyWith(
      targetDate: resolvedDate,
      targetStart: resolvedStart,
      pointerGlobalPosition: globalPosition,
      clearTarget: resolvedDate == null || resolvedStart == null,
    );
  }

  /// Whether placing [dragged] at [date]/[start] would overlap another
  /// block already on [date].
  bool _overlapsExisting(TimeObject dragged, DateTime date, DateTime start) {
    final blocks = ref.read(dayBlocksProvider(date)).value;
    if (blocks == null) return false;
    final end = start.add(dragged.end.difference(dragged.start));
    return blocks.any(
      (block) => block.id != dragged.id && block.overlaps(start, end),
    );
  }

  /// Commits the current drag: moves the block to its current landzone
  /// date/time via the repository, refreshes both the origin and target
  /// day's blocks, then clears the drag. Does nothing if no drag is in
  /// progress; cancels instead if there is no valid landzone.
  Future<void> drop() async {
    final current = state;
    if (current == null) return;
    final toDate = current.targetDate;
    final newStart = current.targetStart;
    if (toDate == null || newStart == null) {
      cancel();
      return;
    }
    // TODO(alex): clearing the drag state before awaiting `repository.move()`
    // means a failing `move` would surface as an unhandled async error and
    // a silent UI no-op (the block snaps back with no explanation). Fine
    // for today's in-memory stub, which cannot fail; must be revisited
    // before any real or networked repository backs this.
    state = null;
    _releasePointer();

    final duration = current.block.end.difference(current.block.start);
    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.move(
      current.block,
      fromDate: current.originalDate,
      toDate: toDate,
      newStart: newStart,
      newEnd: newStart.add(duration),
    );

    ref.invalidate(dayBlocksProvider(current.originalDate));
    ref.invalidate(dayBlocksProvider(toDate));
    await ref.read(dayBlocksProvider(current.originalDate).future);
    await ref.read(dayBlocksProvider(toDate).future);
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

  /// Removes the global route, if any. Safe to call repeatedly, and never
  /// touches [GestureBinding] unless a route was actually registered (so
  /// binding-free unit tests can use this notifier).
  void _releasePointer() {
    final route = _globalRoute;
    if (route != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(route);
    }
    _globalRoute = null;
    _pointer = null;
    _resolveTarget = null;
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

    // `event.position` on a raw PointerEvent routed globally is already in
    // global (screen) coordinates.
    if (event is PointerMoveEvent) {
      final target = _resolveTarget?.call(event.position);
      // No valid column under the pointer right now: fall back to the
      // block's own original date/time so the landzone previews the
      // snap-back instead of disappearing. This only changes what's
      // *displayed* — release still re-resolves fresh and cancels for
      // real if the pointer is still outside every column then (below).
      updatePointer(
        event.position,
        targetDate: target?.date ?? current.originalDate,
        targetStart: target?.start ?? current.block.start,
      );
    } else if (event is PointerUpEvent) {
      final target = _resolveTarget?.call(event.position);
      if (target == null) {
        cancel();
      } else {
        updatePointer(
          event.position,
          targetDate: target.date,
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

/// Projects [dragState] to the value a `DayGrid` for [date] actually cares
/// about, collapsing to `null` whenever [date] is neither the drag's origin
/// nor its current landzone target.
///
/// Meant to be passed to `dragStateProvider.select(...)` so a day column
/// only rebuilds while a drag actually touches it, instead of on every
/// pointer move of a drag happening on some other, unrelated day.
DragState? dragStateForDate(DragState? dragState, DateTime date) {
  if (dragState == null) return null;
  final relevant =
      dragState.originalDate == date || dragState.targetDate == date;
  return relevant ? dragState : null;
}

/// Tracks the block currently being resized by dragging one of its edges,
/// if any.
///
/// `null` when no resize is in progress. A resize never changes a block's
/// date, so unlike [DragNotifier] this needs no pointer-ownership dance —
/// the widget driving the drag stays mounted for its whole lifetime.
class ResizeNotifier extends Notifier<ResizeState?> {
  @override
  ResizeState? build() => null;

  /// Begins resizing [block] on [date] from [edge]. The draft starts out
  /// equal to the block's own current start/end.
  void start({
    required TimeObject block,
    required DateTime date,
    required ResizeEdge edge,
  }) {
    state = ResizeState(
      block: block,
      date: date,
      edge: edge,
      draftStart: block.start,
      draftEnd: block.end,
    );
  }

  /// Updates the dragged edge's draft time to [candidate] (already snapped
  /// to the 15-minute grid), clamped so the block never shrinks below
  /// [_minBlockDuration] and never overlaps another block on [ResizeState.
  /// date].
  void update(DateTime candidate) {
    final current = state;
    if (current == null) return;
    final others = (ref.read(dayBlocksProvider(current.date)).value ?? [])
        .where((block) => block.id != current.block.id);

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

  /// Commits the current resize: persists the draft start/end via the
  /// repository, refreshes the date's blocks, then clears the resize. Does
  /// nothing if no resize is in progress.
  Future<void> commit() async {
    final current = state;
    if (current == null) return;
    state = null;

    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.move(
      current.block,
      fromDate: current.date,
      toDate: current.date,
      newStart: current.draftStart,
      newEnd: current.draftEnd,
    );

    ref.invalidate(dayBlocksProvider(current.date));
    await ref.read(dayBlocksProvider(current.date).future);
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

/// Projects [resizeState] to the value a `DayGrid` for [date] actually cares
/// about, collapsing to `null` whenever the resize belongs to some other
/// date. See [dragStateForDate], its drag equivalent.
ResizeState? resizeStateForDate(ResizeState? resizeState, DateTime date) {
  if (resizeState == null) return null;
  return resizeState.date == date ? resizeState : null;
}
