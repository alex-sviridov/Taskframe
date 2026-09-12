import 'package:taskframe/features/day/models/time_object.dart';

/// One template block rebased onto a target day, ready to pass to
/// `DayBlocksNotifier.addBlock`.
typedef TemplateApplyBlock = ({
  DateTime start,
  DateTime end,
  BlockKind kind,
  String title,
  String categoryId,
});

/// The half-open `[start, end)` range a skipped template block would have
/// occupied on the target day, for driving its "not applied" animation.
typedef TemplateApplySkip = ({DateTime start, DateTime end});

/// The outcome of applying a template to a day: the ids of the blocks
/// actually added, and the ranges of any skipped (overlapping) ones.
typedef TemplateApplyResult = ({
  List<String> addedIds,
  List<TemplateApplySkip> skipped,
});

/// Resolves applying [templateBlocks] (a template's own timeline, dated on
/// [templateAnchorDate]) onto [date]: each block's time-of-day is rebased
/// onto [date], then accepted into [toAdd] unless it overlaps [dayBlocks]
/// or a block already accepted earlier in this same batch, in which case
/// its rebased range is recorded in [skipped] instead.
///
/// Partial application — one conflicting block never blocks the rest of
/// the template from being applied.
({List<TemplateApplyBlock> toAdd, List<TemplateApplySkip> skipped})
resolveTemplateApply({
  required List<TimeObject> templateBlocks,
  required List<TimeObject> dayBlocks,
  required DateTime date,
}) {
  final toAdd = <TemplateApplyBlock>[];
  final skipped = <TemplateApplySkip>[];

  for (final block in templateBlocks) {
    final duration = block.end.difference(block.start);
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      block.start.hour,
      block.start.minute,
    );
    final end = start.add(duration);

    final overlapsExisting = dayBlocks.any((b) => b.overlaps(start, end));
    final overlapsAccepted = toAdd.any(
      (b) => start.isBefore(b.end) && end.isAfter(b.start),
    );

    if (overlapsExisting || overlapsAccepted) {
      skipped.add((start: start, end: end));
    } else {
      toAdd.add((
        start: start,
        end: end,
        kind: block.kind,
        title: block.title,
        categoryId: block.categoryId,
      ));
    }
  }

  return (toAdd: toAdd, skipped: skipped);
}
