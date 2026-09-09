import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/features/day/date_format.dart';
import 'package:taskframe/features/day/day_grid_sizing.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';

/// Below this, a 15-minute slot stops being visually distinct, so the grid
/// scrolls instead of shrinking further.
const _minSlotHeight = 8.0;

/// The day view: a date header with switch arrows above a 15-minute grid
/// of the day's blocks.
class DayScreen extends ConsumerWidget {
  /// Creates a [DayScreen].
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final settings = ref.watch(daySettingsProvider);
    final blocksAsync = ref.watch(dayBlocksProvider(date));

    void shiftDate(int days) =>
        ref.read(selectedDateProvider.notifier).shiftBy(days);

    return Scaffold(
      appBar: AppBar(title: const Text('Day Frame')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous day',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => shiftDate(-1),
                ),
                Text(
                  key: const Key('day-screen-date-label'),
                  formatDayLabel(date),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  tooltip: 'Next day',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => shiftDate(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slotCount =
                    (settings.dayEndHour - settings.dayStartHour) * 4;
                final slotHeight = resolveSlotHeight(
                  availableHeight: constraints.maxHeight,
                  slotCount: slotCount,
                  minSlotHeight: _minSlotHeight,
                );

                return blocksAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text('Failed to load: $error')),
                  data: (blocks) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: DayGrid(
                      date: date,
                      blocks: blocks,
                      settings: settings,
                      slotHeight: slotHeight,
                      onSwipeDay: shiftDate,
                      onCreateBlock:
                          ({required start, required end, required kind}) {
                            unawaited(
                              ref
                                  .read(dayBlocksProvider(date).notifier)
                                  .addBlock(start: start, end: end, kind: kind),
                            );
                          },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
