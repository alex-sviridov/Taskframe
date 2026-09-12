import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/template_apply.dart';

/// How long a newly-applied block's border pulse animation runs.
const templateApplyHighlightDuration = Duration(milliseconds: 600);

/// How long a skipped template block's "not applied" ghost animation runs.
const templateApplyGhostDuration = Duration(milliseconds: 700);

/// A skipped template block rendered transiently at its would-be slot,
/// identified by [id] so its animation's completion can remove exactly
/// this ghost (and no other queued at the same time) from state.
class TemplateApplyGhost {
  /// Creates a [TemplateApplyGhost].
  const TemplateApplyGhost({
    required this.id,
    required this.start,
    required this.end,
  });

  /// Unique within a single [TemplateApplyEffectsNotifier]'s lifetime.
  final int id;

  /// The half-open `[start, end)` range this ghost occupies on the grid.
  final DateTime start;

  /// See [start].
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is TemplateApplyGhost &&
      other.id == id &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, start, end);
}

/// The in-flight "template applied" animation state for one day: which
/// blocks should pulse their border as newly added, and which skipped
/// template events should show a ghost.
class TemplateApplyEffectsState {
  /// Creates a [TemplateApplyEffectsState].
  const TemplateApplyEffectsState({
    this.highlightedIds = const {},
    this.ghosts = const [],
  });

  /// Ids of blocks currently playing their newly-applied border pulse.
  final Set<String> highlightedIds;

  /// Skipped template events currently playing their ghost animation.
  final List<TemplateApplyGhost> ghosts;
}

/// Holds one day's [TemplateApplyEffectsState], populated when a template
/// is applied to it and drained as each block/ghost's own animation
/// widget finishes and calls [removeHighlight]/[removeGhost].
class TemplateApplyEffectsNotifier extends Notifier<TemplateApplyEffectsState> {
  /// Creates a [TemplateApplyEffectsNotifier] for [date].
  TemplateApplyEffectsNotifier(this.date);

  /// The date this notifier's effects belong to.
  final DateTime date;

  int _nextGhostId = 0;

  @override
  TemplateApplyEffectsState build() => const TemplateApplyEffectsState();

  /// Marks [blockIds] as newly applied, so their `DayGrid` blocks render
  /// the highlight animation.
  void addHighlights(Iterable<String> blockIds) {
    state = TemplateApplyEffectsState(
      highlightedIds: {...state.highlightedIds, ...blockIds},
      ghosts: state.ghosts,
    );
  }

  /// Stops highlighting [blockId] — called once its pulse animation
  /// completes.
  void removeHighlight(String blockId) {
    state = TemplateApplyEffectsState(
      highlightedIds: state.highlightedIds.difference({blockId}),
      ghosts: state.ghosts,
    );
  }

  /// Queues a ghost for each of [skips], returning them (with freshly
  /// assigned ids) so the caller can key their animation widgets.
  List<TemplateApplyGhost> addGhosts(Iterable<TemplateApplySkip> skips) {
    final added = [
      for (final skip in skips)
        TemplateApplyGhost(
          id: _nextGhostId++,
          start: skip.start,
          end: skip.end,
        ),
    ];
    state = TemplateApplyEffectsState(
      highlightedIds: state.highlightedIds,
      ghosts: [...state.ghosts, ...added],
    );
    return added;
  }

  /// Removes the ghost identified by [ghostId] — called once its
  /// animation completes.
  void removeGhost(int ghostId) {
    state = TemplateApplyEffectsState(
      highlightedIds: state.highlightedIds,
      ghosts: state.ghosts.where((g) => g.id != ghostId).toList(),
    );
  }
}

/// The in-flight template-apply animation state for a given date.
final templateApplyEffectsProvider =
    NotifierProvider.family<
      TemplateApplyEffectsNotifier,
      TemplateApplyEffectsState,
      DateTime
    >(TemplateApplyEffectsNotifier.new);
