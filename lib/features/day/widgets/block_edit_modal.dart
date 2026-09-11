import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/responsive.dart';
import 'package:taskframe/features/category/models/category.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/day/date_format.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/widgets/block_kind_style.dart';
import 'package:taskframe/features/day/widgets/schedule_block_actions.dart';

/// A small color dot for [category] followed by its emoji-prefixed name,
/// used for every row of [BlockCategoryPicker] — the closed field, its
/// dropdown menu items, and its wheel entries alike — so they never drift
/// out of visual sync with each other. Color is an accent (a swatch), not
/// the row's whole background, so it reads as a standard field/menu row
/// rather than a colored block.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 8, backgroundColor: Color(category.colorValue)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            category.formatTitle(category.name),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The shared field chrome (outline + "Category" label) both the wide
/// dropdown and the narrow wheel-picker trigger sit inside, so the two
/// read as the same kind of control regardless of width.
const _fieldDecoration = InputDecoration(
  labelText: 'Category',
  border: OutlineInputBorder(),
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
);

/// Lets the user assign a category to the block being edited: a standard
/// [DropdownButtonFormField] on a wide width, or — since a dropdown menu
/// is awkward to operate with a finger — the same field chrome wrapping a
/// tappable row that opens a [CupertinoPicker] wheel on a narrow one.
/// Either way every row is a [_CategoryRow], and picking one calls
/// [onSelected] immediately, no separate confirm step, matching the block
/// edit modal's other selectors.
class BlockCategoryPicker extends ConsumerWidget {
  /// Creates a [BlockCategoryPicker].
  const BlockCategoryPicker({
    required this.selectedCategoryId,
    required this.onSelected,
    super.key,
  });

  /// The id of the category currently assigned to the block being edited.
  final String selectedCategoryId;

  /// Called with a category's id when a new one is picked.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryListProvider).value ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();
    final selected = categoryById(categories, selectedCategoryId);

    if (isNarrow(context)) {
      return InputDecorator(
        decoration: _fieldDecoration,
        child: GestureDetector(
          onTap: () => _showWheelPicker(context, categories, selected.id),
          child: _CategoryRow(category: selected),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      // Forces the field to reset to [selected.id] whenever it changes
      // for a reason other than this field's own [onChanged] — e.g. the
      // block being edited changes underneath it — since a FormField
      // otherwise only reads [initialValue] on its very first build.
      key: ValueKey(selected.id),
      initialValue: selected.id,
      decoration: _fieldDecoration,
      selectedItemBuilder: (context) => [
        for (final category in categories) _CategoryRow(category: category),
      ],
      items: [
        for (final category in categories)
          DropdownMenuItem(
            value: category.id,
            child: _CategoryRow(category: category),
          ),
      ],
      onChanged: (id) {
        if (id != null) onSelected(id);
      },
    );
  }

  /// Opens a bottom sheet containing a [CupertinoPicker] wheel of every
  /// category, initially centered on [selectedId]. Applies [onSelected]
  /// on every settle, same as scrolling the block edit modal's own time
  /// wheels — there's no separate Done/confirm action.
  Future<void> _showWheelPicker(
    BuildContext context,
    List<Category> categories,
    String selectedId,
  ) {
    final initialItem = categories.indexWhere((c) => c.id == selectedId);
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 216,
          child: CupertinoPicker(
            itemExtent: 48,
            scrollController: FixedExtentScrollController(
              initialItem: initialItem < 0 ? 0 : initialItem,
            ),
            onSelectedItemChanged: (index) => onSelected(categories[index].id),
            children: [
              for (final category in categories)
                Center(child: _CategoryRow(category: category)),
            ],
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
    return ListTile(
      title: Text(label),
      trailing: Text(
        formatHm(time),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: onTap,
    );
  }
}

/// A labeled dropdown field listing every 15-minute mark within [range]
/// (see [validEditRange]) — so a value that would push the block past its
/// neighbor or the day's own bounds is never offered — used in place of
/// [BlockTimeRow] and its wheel picker on a wide width, where dragging a
/// wheel with a mouse is awkward and an inline-expanding picker pushes
/// the rest of the modal's layout around. Selecting an item calls
/// [onChanged] immediately, no separate confirm step.
class BlockTimeDropdown extends StatelessWidget {
  /// Creates a [BlockTimeDropdown].
  const BlockTimeDropdown({
    required this.label,
    required this.value,
    required this.range,
    required this.onChanged,
    super.key,
  });

  /// The field's label, e.g. "Starts".
  final String label;

  /// The currently selected time; must be one of [_quarterHourMarks]
  /// within [range] (guaranteed since both are always derived from the
  /// same on-grid [TimeObject] field).
  final DateTime value;

  /// The contiguous range [value] may move within.
  final ({DateTime start, DateTime end}) range;

  /// Called with the newly picked time when a different one is selected.
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = _quarterHourMarks(range.start, range.end);
    return DropdownButtonFormField<DateTime>(
      // Forces the field to reset to [value] whenever it changes for a
      // reason other than this field's own [onChanged] — see the same
      // pattern (and why) on `BlockCategoryPicker`'s dropdown.
      key: ValueKey(value),
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(formatHm(option))),
      ],
      onChanged: (picked) {
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// Every 15-minute mark from [start] to [end] inclusive. Both must already
/// fall on the 15-minute grid (true of every [TimeObject] field and
/// [validEditRange] bound), so this never needs to snap either one.
List<DateTime> _quarterHourMarks(DateTime start, DateTime end) => [
  for (var t = start; !t.isAfter(end); t = t.add(const Duration(minutes: 15)))
    t,
];

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

/// Opens the block edit modal for [block] (which belongs to [column]):
/// title, start/end, and delete — plus, for a [DayColumn], copy-to-next-day
/// and a date row. Near-fullscreen on a narrow (mobile) width, a centered
/// fixed-width dialog on a wide one.
Future<void> showBlockEditModal({
  required BuildContext context,
  required ScheduleColumn column,
  required ScheduleBlockActions actions,
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
        child: BlockEditModal(
          column: column,
          actions: actions,
          initialBlock: block,
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: BlockEditModal(
          column: column,
          actions: actions,
          initialBlock: block,
        ),
      ),
    ),
  );
}

/// The block edit modal's content: title, category picker, start/end
/// rows, and copy/delete actions. Reads the live block from
/// [ScheduleBlockActions.watchBlocks] by [initialBlock]'s id on every
/// rebuild — [initialBlock] itself is only the optimistic value shown
/// before that provider's first load completes. Closes itself if the
/// block disappears from a loaded list (e.g. deleted from elsewhere).
class BlockEditModal extends ConsumerStatefulWidget {
  /// Creates a [BlockEditModal] for the block identified by
  /// [initialBlock]'s id, belonging to [column].
  const BlockEditModal({
    required this.column,
    required this.actions,
    required this.initialBlock,
    super.key,
  });

  /// The column [initialBlock] belongs to.
  final ScheduleColumn column;

  /// Reads/writes [initialBlock]'s title/category/kind/start/end/delete.
  final ScheduleBlockActions actions;

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

  /// The column whose provider this modal currently watches/writes
  /// through. Starts at [BlockEditModal.column] (a `final` constructor
  /// param that can't itself change) and is reassigned by [_changeDate]
  /// after a cross-day move (day columns only), so the modal keeps
  /// showing the same block on its new date instead of the move looking
  /// like the block was deleted.
  late ScheduleColumn _currentColumn;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialBlock.title);
    _titleFocus = FocusNode()..addListener(_handleFocusChange);
    _autofocusTitle = widget.initialBlock.title.trim().isEmpty;
    _currentColumn = widget.column;
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
      await widget.actions.updateBlock(
        ref,
        _currentColumn,
        block,
        title: value,
      );
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
  /// picked, moves [block] there directly via the day repository (this is
  /// only ever reachable when [widget.column] is a [DayColumn] — see the
  /// date row's guard in `build`) — the same move-and-refresh pattern
  /// `DragNotifier.drop` uses for a drag-and-drop move — then switches
  /// [_currentColumn] to the new date. Only the calendar itself closes;
  /// the modal stays open, now reading/writing through the new date's
  /// provider.
  Future<void> _changeDate(TimeObject block) async {
    await _commitTitle(block);
    if (!mounted) return;
    final currentDate = (_currentColumn as DayColumn).date;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(currentDate.year - 5),
      lastDate: DateTime(currentDate.year + 5),
    );
    if (picked == null || !mounted) return;

    final newDate = DateTime(picked.year, picked.month, picked.day);
    if (newDate == currentDate) return;

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
      fromDate: currentDate,
      toDate: newDate,
      newStart: newStart,
      newEnd: newStart.add(duration),
    );

    ref.invalidate(dayBlocksProvider(currentDate));
    ref.invalidate(dayBlocksProvider(newDate));
    await ref.read(dayBlocksProvider(currentDate).future);
    await ref.read(dayBlocksProvider(newDate).future);
    if (!mounted) return;
    setState(() => _currentColumn = DayColumn(newDate));
  }

  Future<void> _confirmTime(
    TimeObject block,
    _TimeField field,
    DateTime picked,
  ) async {
    await widget.actions.updateBlock(
      ref,
      _currentColumn,
      block,
      start: field == _TimeField.start ? picked : null,
      end: field == _TimeField.end ? picked : null,
    );
  }

  Future<void> _setKind(TimeObject block, BlockKind kind) async {
    if (kind == block.kind) return;
    await widget.actions.updateBlock(ref, _currentColumn, block, kind: kind);
  }

  Future<void> _setCategory(TimeObject block, String categoryId) async {
    if (categoryId == block.categoryId) return;
    await widget.actions.updateBlock(
      ref,
      _currentColumn,
      block,
      categoryId: categoryId,
    );
  }

  /// Copies [block] to the following calendar day. Only ever reachable
  /// when [widget.column] is a [DayColumn] — see the copy button's guard
  /// in `build`.
  Future<void> _copyToNextDay(TimeObject block) async {
    await _commitTitle(block);
    if (!mounted) return;
    final currentDate = (_currentColumn as DayColumn).date;
    final blocks = ref.read(dayBlocksProvider(currentDate)).value;
    final toCopy = blocks == null
        ? block
        : (_findById(blocks, block.id) ?? block);
    await ref
        .read(dayBlocksProvider(currentDate).notifier)
        .copyToNextDay(toCopy);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied to next day')));
  }

  Future<void> _delete(TimeObject block) async {
    await widget.actions.deleteBlock(ref, _currentColumn, block);
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
    final blocks = widget.actions.watchBlocks(ref, _currentColumn);
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
    final isDayColumn = widget.column is DayColumn;
    bool canCopy = false;
    if (isDayColumn) {
      final currentDate = (_currentColumn as DayColumn).date;
      final nextDate = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day + 1,
      );
      final nextDayBlocks = ref.watch(dayBlocksProvider(nextDate)).value;
      canCopy =
          nextDayBlocks != null &&
          !copyToNextDayWouldOverlap(
            block: current,
            nextDate: nextDate,
            nextDayBlocks: nextDayBlocks,
          );
    }
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
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _titleController,
                focusNode: _titleFocus,
                autofocus: _autofocusTitle,
                onSubmitted: (_) => _commitTitle(current),
                decoration: const InputDecoration(
                  border: UnderlineInputBorder(),
                  isDense: true,
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              BlockCategoryPicker(
                selectedCategoryId: current.categoryId,
                onSelected: (categoryId) => _setCategory(current, categoryId),
              ),
              const SizedBox(height: 12),
              if (isDayColumn) ...[
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(
                    formatDate(
                      (_currentColumn as DayColumn).date,
                      settings.dateFormat,
                    ),
                  ),
                  onTap: () => _changeDate(current),
                ),
              ],
              if (isNarrow(context)) ...[
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
                      day: anchorDateFor(_currentColumn),
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
                      day: anchorDateFor(_currentColumn),
                      settings: settings,
                      others: others,
                    ),
                    onDone: (picked) =>
                        _confirmTime(current, _TimeField.end, picked),
                  ),
              ] else ...[
                // A drag-to-scroll wheel is awkward with a mouse and, as an
                // inline-expanding picker, pushes the rest of this layout
                // around — a plain dropdown avoids both on a wide width.
                BlockTimeDropdown(
                  label: 'Starts',
                  value: current.start,
                  range: validEditRange(
                    block: current,
                    editingStart: true,
                    day: anchorDateFor(_currentColumn),
                    settings: settings,
                    others: others,
                  ),
                  onChanged: (picked) =>
                      _confirmTime(current, _TimeField.start, picked),
                ),
                const SizedBox(height: 12),
                BlockTimeDropdown(
                  label: 'Ends',
                  value: current.end,
                  range: validEditRange(
                    block: current,
                    editingStart: false,
                    day: anchorDateFor(_currentColumn),
                    settings: settings,
                    others: others,
                  ),
                  onChanged: (picked) =>
                      _confirmTime(current, _TimeField.end, picked),
                ),
              ],
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
                  if (isDayColumn)
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
