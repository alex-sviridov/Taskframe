import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taskframe/features/day/day_settings.dart';

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

  List<int> get _hours => [
    for (var h = widget.settings.dayStartHour; h <= widget.settings.dayEndHour; h++) h,
  ];

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    _quarterIndex = widget.initial.minute ~/ 15;
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
                      controller: FixedExtentScrollController(
                        initialItem: hours.indexOf(_hour),
                      ),
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
                      controller: FixedExtentScrollController(
                        initialItem: _quarterIndex,
                      ),
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
