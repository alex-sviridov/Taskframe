import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/day/date_format.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/widgets/block_kind_style.dart';

/// A fixed-height row of empty, non-interactive rounded squares reserving
/// visual space for a future category carousel. Carries no data model or
/// selection state yet.
class BlockCategoryPlaceholder extends StatelessWidget {
  /// Creates a [BlockCategoryPlaceholder].
  const BlockCategoryPlaceholder({super.key});

  static const double _size = 40;
  static const int _count = 5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _count,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

/// A tappable row showing [label] and [time] as `HH:mm`, used for the
/// block edit modal's start/end rows.
class BlockTimeRow extends StatelessWidget {
  /// Creates a [BlockTimeRow].
  const BlockTimeRow({
    required this.label,
    required this.time,
    required this.onTap,
    super.key,
  });

  /// The row's leading label, e.g. "Starts".
  final String label;

  /// The time shown, formatted as `HH:mm`.
  final DateTime time;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    return ListTile(
      title: Text(label),
      trailing: Text(text, style: Theme.of(context).textTheme.titleMedium),
      onTap: onTap,
    );
  }
}

/// The 15-minute grid values a minute wheel can ever offer.
const _quarterMinutes = [0, 15, 30, 45];

/// An inline hour/minute-in-15-increments wheel picker, shown expanded
/// beneath one of the block edit modal's time rows. Only offers hours and
/// minutes that fall within [range] (see [validEditRange]) — so a value
/// that would push the block past its neighbor or the day's own bounds is
/// never reachable — and renders whichever value is currently centered in
/// each wheel bolder and larger than the rest, so scrolling shows clearly
/// what's selected.
class _TimeWheelPicker extends StatefulWidget {
  const _TimeWheelPicker({
    required this.initial,
    required this.settings,
    required this.range,
    required this.onDone,
  });

  final DateTime initial;
  final DaySettings settings;

  /// The contiguous range [initial]'s hour/minute may move within; see
  /// [validEditRange].
  final ({DateTime start, DateTime end}) range;

  /// Called with the picked time on every scroll change to either wheel —
  /// there's no separate confirm step; the caller applies each value as
  /// soon as it's dialed in. Tapping the row again (outside this widget)
  /// is what hides the picker.
  final ValueChanged<DateTime> onDone;

  @override
  State<_TimeWheelPicker> createState() => _TimeWheelPickerState();
}

class _TimeWheelPickerState extends State<_TimeWheelPicker> {
  /// Computed once from [_TimeWheelPicker.range] — fixed for the picker's
  /// whole lifetime, so this is never recomputed mid-scroll.
  late final List<int> _hours;

  late int _hour;

  /// The valid quarters for [_hour] specifically — recomputed only when
  /// [_hour] changes (via [_selectHour]), not on every minute-wheel scroll.
  late List<int> _quarters;
  late int _quarterIndex;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  /// Whether a quarter-hour value at [hour]:[minute] falls within
  /// [_TimeWheelPicker.range].
  bool _isValid(int hour, int minute) {
    final t = DateTime(
      widget.initial.year,
      widget.initial.month,
      widget.initial.day,
      hour,
      minute,
    );
    return !t.isBefore(widget.range.start) && !t.isAfter(widget.range.end);
  }

  List<int> _quartersFor(int hour) => [
    for (final m in _quarterMinutes)
      if (_isValid(hour, m)) m,
  ];

  @override
  void initState() {
    super.initState();
    _hours = [
      for (
        var h = widget.settings.dayStartHour;
        h <= widget.settings.dayEndHour;
        h++
      )
        if (_quartersFor(h).isNotEmpty) h,
    ];
    _hour = widget.initial.hour;
    _quarters = _quartersFor(_hour);
    _quarterIndex = _quarters.indexOf(widget.initial.minute);
    _hourController = FixedExtentScrollController(
      initialItem: _hours.indexOf(_hour),
    );
    _minuteController = FixedExtentScrollController(initialItem: _quarterIndex);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  /// Calls [_TimeWheelPicker.onDone] with the currently dialed-in hour and
  /// quarter, applying it immediately — there's no separate confirm step.
  void _applyCurrent() {
    widget.onDone(
      DateTime(
        widget.initial.year,
        widget.initial.month,
        widget.initial.day,
        _hour,
        _quarters[_quarterIndex],
      ),
    );
  }

  /// Applies a new hour selection, recomputing the minute wheel's valid
  /// quarters for it and — if the previously selected minute isn't one of
  /// them — snapping to whichever of the new quarters is closest, then
  /// repositions the minute wheel to match once the frame settles (jumping
  /// it mid-callback would fight the hour wheel's own scroll settling).
  void _selectHour(int hour) {
    final oldMinute = _quarters[_quarterIndex];
    final newQuarters = _quartersFor(hour);
    var newIndex = newQuarters.indexOf(oldMinute);
    if (newIndex == -1) {
      newIndex = 0;
      var bestDiff = (newQuarters[0] - oldMinute).abs();
      for (var i = 1; i < newQuarters.length; i++) {
        final diff = (newQuarters[i] - oldMinute).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          newIndex = i;
        }
      }
    }
    setState(() {
      _hour = hour;
      _quarters = newQuarters;
      _quarterIndex = newIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _minuteController.jumpToItem(newIndex);
    });
    _applyCurrent();
  }

  Widget _wheelText(String text, {required bool selected}) => Center(
    child: Text(
      text,
      style: TextStyle(
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: selected ? 22 : 16,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 220,
        child: Row(
          children: [
            Expanded(
              child: ListWheelScrollView(
                itemExtent: 40,
                controller: _hourController,
                onSelectedItemChanged: (index) => _selectHour(_hours[index]),
                children: [
                  for (final h in _hours)
                    _wheelText(
                      h.toString().padLeft(2, '0'),
                      selected: h == _hour,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListWheelScrollView(
                itemExtent: 40,
                controller: _minuteController,
                onSelectedItemChanged: (index) {
                  setState(() => _quarterIndex = index);
                  _applyCurrent();
                },
                children: [
                  for (final m in _quarters)
                    _wheelText(
                      m.toString().padLeft(2, '0'),
                      selected: m == _quarters[_quarterIndex],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A delete icon button that requires two taps within [_confirmWindow] to
/// call [onConfirmed] — no separate confirmation dialog. The first tap
/// swaps the icon/tooltip into a "confirming" state and starts a timer; a
/// second tap before it lapses confirms, letting it lapse reverts.
class BlockDeleteButton extends StatefulWidget {
  /// Creates a [BlockDeleteButton].
  const BlockDeleteButton({required this.onConfirmed, super.key});

  /// Called when the second tap lands within the confirm window.
  final VoidCallback onConfirmed;

  @override
  State<BlockDeleteButton> createState() => _BlockDeleteButtonState();
}

class _BlockDeleteButtonState extends State<BlockDeleteButton> {
  static const _confirmWindow = Duration(seconds: 3);

  bool _confirming = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (_confirming) {
      _timer?.cancel();
      setState(() => _confirming = false);
      widget.onConfirmed();
      return;
    }
    setState(() => _confirming = true);
    _timer = Timer(_confirmWindow, () {
      if (mounted) setState(() => _confirming = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _confirming ? 'Tap again to delete' : 'Delete',
      icon: Icon(
        _confirming ? Icons.warning_amber : Icons.delete_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      onPressed: _handleTap,
    );
  }
}

/// Opens the block edit modal for [block] (which belongs to [date]):
/// title, start/end, copy-to-next-day and delete. Near-fullscreen on a
/// narrow (mobile) width, a centered fixed-width dialog on a wide one.
Future<void> showBlockEditModal({
  required BuildContext context,
  required DateTime date,
  required TimeObject block,
}) {
  if (isNarrow(context)) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.95,
        child: BlockEditModal(date: date, initialBlock: block),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: BlockEditModal(date: date, initialBlock: block),
      ),
    ),
  );
}

/// The block edit modal's content: title, category placeholder, start/end
/// rows, and copy/delete actions. Reads the live block from
/// `dayBlocksProvider(date)` by [initialBlock]'s id on every rebuild —
/// [initialBlock] itself is only the optimistic value shown before that
/// provider's first load completes. Closes itself if the block disappears
/// from a loaded list (e.g. deleted from elsewhere).
class BlockEditModal extends ConsumerStatefulWidget {
  /// Creates a [BlockEditModal] for the block identified by
  /// [initialBlock]'s id, belonging to [date].
  const new({required this.date, required this.initialBlock, super.key});

  /// The date [initialBlock] belongs to.
  final DateTime date;

  /// The block as known when the modal was opened.
  final TimeObject initialBlock;

  @override
  ConsumerState<BlockEditModal> createState() => _BlockEditModalState();
}

/// Which of the modal's two time rows, if any, currently has its wheel
/// picker expanded inline beneath it.
enum _TimeField { start, end }

class _BlockEditModalState extends ConsumerState<BlockEditModal> {
  late final TextEditingController _titleController;
  late final FocusNode _titleFocus;
  TimeObject? _currentBlock;
  _TimeField? _expandedField;

  /// The date whose provider this modal currently watches/writes through.
  /// Starts at [BlockEditModal.date] (a `final` constructor param that
  /// can't itself change) and is reassigned by [_changeDate] after a
  /// cross-day move, so the modal keeps showing the same block on its new
  /// date instead of the move looking like the block was deleted.
  late DateTime _currentDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialBlock.title);
    _titleFocus = FocusNode()..addListener(_handleFocusChange);
    _autofocusTitle = widget.initialBlock.title.trim().isEmpty;
    _currentDate = widget.date;
  }

  @override
  void dispose() {
    _titleFocus
      ..removeListener(_handleFocusChange)
      ..dispose();
    _titleController.dispose();
    super.dispose();
  }

  /// Whether the title field should grab focus on this build — only true
  /// once, right after opening a block whose title is still empty (a
  /// freshly created one), so re-opening an already-titled block never
  /// pops the keyboard unexpectedly.
  bool _autofocusTitle = false;

  void _handleFocusChange() {
    final block = _currentBlock;
    if (!_titleFocus.hasFocus && block != null) {
      unawaited(_commitTitle(block));
    }
  }

  Future<void> _commitTitle(TimeObject block) async {
    final value = _titleController.text.trim();
    if (value.isEmpty) {
      _titleController.text = block.title;
      return;
    }
    if (value != block.title) {
      await ref
          .read(dayBlocksProvider(_currentDate).notifier)
          .updateBlock(block, title: value);
    }
  }

  /// Toggles [field]'s inline wheel picker: collapses it if already
  /// expanded (a cancel, matching the old sheet's dismiss-without-
  /// confirming behavior), otherwise commits any pending title edit first
  /// and expands it — collapsing whichever other field was expanded, so
  /// only one shows at a time.
  Future<void> _toggleTimeField(_TimeField field, TimeObject block) async {
    if (_expandedField == field) {
      setState(() => _expandedField = null);
      return;
    }
    await _commitTitle(block);
    if (!mounted) return;
    setState(() => _expandedField = field);
  }

  /// Opens the standard Material date picker and, if a different date is
  /// picked, moves [block] there via the repository — the same
  /// move-and-refresh pattern [DragNotifier.drop] uses for a drag-and-drop
  /// move — then switches [_currentDate] to it. Only the calendar itself
  /// closes; the modal stays open, now reading/writing through the new
  /// date's provider.
  Future<void> _changeDate(TimeObject block) async {
    await _commitTitle(block);
    if (!mounted) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentDate,
      firstDate: DateTime(_currentDate.year - 5),
      lastDate: DateTime(_currentDate.year + 5),
    );
    if (picked == null || !mounted) return;

    final newDate = DateTime(picked.year, picked.month, picked.day);
    final oldDate = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    if (newDate == oldDate) return;

    final duration = block.end.difference(block.start);
    final newStart = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      block.start.hour,
      block.start.minute,
    );
    final repository = ref.read(dayBlocksRepositoryProvider);
    await repository.move(
      block,
      fromDate: oldDate,
      toDate: newDate,
      newStart: newStart,
      newEnd: newStart.add(duration),
    );

    ref.invalidate(dayBlocksProvider(oldDate));
    ref.invalidate(dayBlocksProvider(newDate));
    await ref.read(dayBlocksProvider(oldDate).future);
    await ref.read(dayBlocksProvider(newDate).future);
    if (!mounted) return;
    setState(() => _currentDate = newDate);
  }

  Future<void> _confirmTime(
    TimeObject block,
    _TimeField field,
    DateTime picked,
  ) async {
    await ref
        .read(dayBlocksProvider(_currentDate).notifier)
        .updateBlock(
          block,
          start: field == _TimeField.start ? picked : null,
          end: field == _TimeField.end ? picked : null,
        );
  }

  Future<void> _setKind(TimeObject block, BlockKind kind) async {
    if (kind == block.kind) return;
    await ref
        .read(dayBlocksProvider(_currentDate).notifier)
        .updateBlock(block, kind: kind);
  }

  Future<void> _copyToNextDay(TimeObject block) async {
    await _commitTitle(block);
    if (!mounted) return;
    // copyToNextDay reads block.title directly, so a just-committed rename
    // must be picked up here — re-fetch by id rather than reusing the
    // pre-commit `block`, whose title field is now stale.
    final blocks = ref.read(dayBlocksProvider(_currentDate)).value;
    final toCopy = blocks == null
        ? block
        : (_findById(blocks, block.id) ?? block);
    await ref
        .read(dayBlocksProvider(_currentDate).notifier)
        .copyToNextDay(toCopy);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied to next day')));
  }

  Future<void> _delete(TimeObject block) async {
    await ref.read(dayBlocksProvider(_currentDate).notifier).deleteBlock(block);
    _currentBlock = null;
    if (mounted) Navigator.of(context).pop();
  }

  TimeObject? _findById(List<TimeObject> blocks, String id) {
    for (final b in blocks) {
      if (b.id == id) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = ref.watch(dayBlocksProvider(_currentDate)).value;
    final block = blocks == null
        ? widget.initialBlock
        : _findById(blocks, widget.initialBlock.id);

    if (blocks != null && block == null) {
      _currentBlock = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }

    final current = block!;
    _currentBlock = current;
    if (!_titleFocus.hasFocus && _titleController.text != current.title) {
      _titleController.text = current.title;
    }

    final settings = ref.watch(daySettingsProvider);
    final nextDate = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day + 1,
    );
    final nextDayBlocks = ref.watch(dayBlocksProvider(nextDate)).value;
    final canCopy =
        nextDayBlocks != null &&
        !copyToNextDayWouldOverlap(
          block: current,
          nextDate: nextDate,
          nextDayBlocks: nextDayBlocks,
        );
    final others = (blocks ?? const <TimeObject>[])
        .where((b) => b.id != current.id)
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                focusNode: _titleFocus,
                autofocus: _autofocusTitle,
                onSubmitted: (_) => _commitTitle(current),
                decoration: const InputDecoration(border: InputBorder.none),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const BlockCategoryPlaceholder(),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(formatDate(_currentDate, settings.dateFormat)),
                onTap: () => _changeDate(current),
              ),
              BlockTimeRow(
                label: 'Starts',
                time: current.start,
                onTap: () => _toggleTimeField(_TimeField.start, current),
              ),
              if (_expandedField == _TimeField.start)
                _TimeWheelPicker(
                  initial: current.start,
                  settings: settings,
                  range: validEditRange(
                    block: current,
                    editingStart: true,
                    day: _currentDate,
                    settings: settings,
                    others: others,
                  ),
                  onDone: (picked) =>
                      _confirmTime(current, _TimeField.start, picked),
                ),
              BlockTimeRow(
                label: 'Ends',
                time: current.end,
                onTap: () => _toggleTimeField(_TimeField.end, current),
              ),
              if (_expandedField == _TimeField.end)
                _TimeWheelPicker(
                  initial: current.end,
                  settings: settings,
                  range: validEditRange(
                    block: current,
                    editingStart: false,
                    day: _currentDate,
                    settings: settings,
                    others: others,
                  ),
                  onDone: (picked) =>
                      _confirmTime(current, _TimeField.end, picked),
                ),
              const SizedBox(height: 12),
              Center(
                child: SegmentedButton<BlockKind>(
                  segments: [
                    for (final kind in BlockKind.values)
                      ButtonSegment(
                        value: kind,
                        label: Text(kind.label),
                        icon: Icon(kind.icon, color: kind.color),
                      ),
                  ],
                  selected: {current.kind},
                  onSelectionChanged: (selection) =>
                      _setKind(current, selection.single),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Copy to next day',
                    icon: const Icon(Icons.content_copy),
                    onPressed: canCopy ? () => _copyToNextDay(current) : null,
                  ),
                  BlockDeleteButton(onConfirmed: () => _delete(current)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
