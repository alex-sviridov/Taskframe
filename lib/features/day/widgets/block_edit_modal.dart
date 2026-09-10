import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/day_new_block.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';

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

/// Opens a bottom sheet with hour/minute-in-15-increments wheels, scrolled
/// initially to [initial]'s hour/minute (rounded down to the nearest 15),
/// bounded by [settings]'s day start/end hour. Returns the picked
/// [DateTime] (same year/month/day as [initial]) if the user taps "Done",
/// or `null` if the sheet is dismissed another way.
Future<DateTime?> showTimeWheelPicker({
  required BuildContext context,
  required DateTime initial,
  required DaySettings settings,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    builder: (context) => _TimeWheelPicker(initial: initial, settings: settings),
  );
}

class _TimeWheelPicker extends StatefulWidget {
  const _TimeWheelPicker({required this.initial, required this.settings});

  final DateTime initial;
  final DaySettings settings;

  @override
  State<_TimeWheelPicker> createState() => _TimeWheelPickerState();
}

class _TimeWheelPickerState extends State<_TimeWheelPicker> {
  late int _hour;
  late int _quarterIndex;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  List<int> get _hours => [
    for (var h = widget.settings.dayStartHour; h <= widget.settings.dayEndHour; h++) h,
  ];

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    _quarterIndex = widget.initial.minute ~/ 15;
    _hourController = FixedExtentScrollController(
      initialItem: _hours.indexOf(_hour),
    );
    _minuteController = FixedExtentScrollController(
      initialItem: _quarterIndex,
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = _hours;
    return SafeArea(
      child: SizedBox(
        height: 260,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: ListWheelScrollView(
                      itemExtent: 40,
                      controller: _hourController,
                      onSelectedItemChanged: (index) =>
                          setState(() => _hour = hours[index]),
                      children: [
                        for (final h in hours)
                          Center(child: Text(h.toString().padLeft(2, '0'))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListWheelScrollView(
                      itemExtent: 40,
                      controller: _minuteController,
                      onSelectedItemChanged: (index) =>
                          setState(() => _quarterIndex = index),
                      children: const [
                        Center(child: Text('00')),
                        Center(child: Text('15')),
                        Center(child: Text('30')),
                        Center(child: Text('45')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(
                DateTime(
                  widget.initial.year,
                  widget.initial.month,
                  widget.initial.day,
                  _hour,
                  _quarterIndex * 15,
                ),
              ),
              child: const Text('Done'),
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

/// Below this viewport width, [showBlockEditModal] shows a near-fullscreen
/// bottom sheet; at or above it, a centered fixed-width dialog.
const _narrowBreakpoint = 700.0;

/// Opens the block edit modal for [block] (which belongs to [date]):
/// title, start/end, copy-to-next-day and delete. Near-fullscreen on a
/// narrow (mobile) width, a centered fixed-width dialog on a wide one.
Future<void> showBlockEditModal({
  required BuildContext context,
  required DateTime date,
  required TimeObject block,
}) {
  final isNarrow = MediaQuery.sizeOf(context).width < _narrowBreakpoint;
  if (isNarrow) {
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

class _BlockEditModalState extends ConsumerState<BlockEditModal> {
  late final TextEditingController _titleController;
  late final FocusNode _titleFocus;
  TimeObject? _currentBlock;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialBlock.title);
    _titleFocus = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _titleFocus
      ..removeListener(_handleFocusChange)
      ..dispose();
    _titleController.dispose();
    super.dispose();
  }

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
          .read(dayBlocksProvider(widget.date).notifier)
          .updateBlock(block, title: value);
    }
  }

  Future<void> _editStart(TimeObject block, DaySettings settings) async {
    await _commitTitle(block);
    if (!mounted) return;
    final picked = await showTimeWheelPicker(
      context: context,
      initial: block.start,
      settings: settings,
    );
    if (picked == null) return;
    await ref
        .read(dayBlocksProvider(widget.date).notifier)
        .updateBlock(block, start: picked);
  }

  Future<void> _editEnd(TimeObject block, DaySettings settings) async {
    await _commitTitle(block);
    if (!mounted) return;
    final picked = await showTimeWheelPicker(
      context: context,
      initial: block.end,
      settings: settings,
    );
    if (picked == null) return;
    await ref
        .read(dayBlocksProvider(widget.date).notifier)
        .updateBlock(block, end: picked);
  }

  Future<void> _copyToNextDay(TimeObject block) async {
    await _commitTitle(block);
    if (!mounted) return;
    // copyToNextDay reads block.title directly, so a just-committed rename
    // must be picked up here — re-fetch by id rather than reusing the
    // pre-commit `block`, whose title field is now stale.
    final blocks = ref.read(dayBlocksProvider(widget.date)).value;
    final toCopy = blocks == null
        ? block
        : (_findById(blocks, block.id) ?? block);
    await ref
        .read(dayBlocksProvider(widget.date).notifier)
        .copyToNextDay(toCopy);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to next day')));
  }

  Future<void> _delete(TimeObject block) async {
    await ref.read(dayBlocksProvider(widget.date).notifier).deleteBlock(block);
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
    final blocks = ref.watch(dayBlocksProvider(widget.date)).value;
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
      widget.date.year,
      widget.date.month,
      widget.date.day + 1,
    );
    final nextDayBlocks = ref.watch(dayBlocksProvider(nextDate)).value;
    final canCopy =
        nextDayBlocks != null &&
        !copyToNextDayWouldOverlap(
          block: current,
          nextDate: nextDate,
          nextDayBlocks: nextDayBlocks,
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    focusNode: _titleFocus,
                    onSubmitted: (_) => _commitTitle(current),
                    decoration: const InputDecoration(border: InputBorder.none),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const BlockCategoryPlaceholder(),
            const SizedBox(height: 12),
            BlockTimeRow(
              label: 'Starts',
              time: current.start,
              onTap: () => _editStart(current, settings),
            ),
            BlockTimeRow(
              label: 'Ends',
              time: current.end,
              onTap: () => _editEnd(current, settings),
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
    );
  }
}
