import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/day_schedule_block_actions.dart';
import 'package:taskframe/features/day/day_schedule_controller.dart';
import 'package:taskframe/features/day/day_settings.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/template_apply_effects.dart';
import 'package:taskframe/features/day/widgets/day_grid.dart';
import 'package:taskframe/features/day/widgets/drag_target_resolver.dart';

const _settings = DaySettings(
  dayStartHour: 6,
  dayEndHour: 23,
  firstDayOfWeek: DateTime.monday,
  dateFormat: 'dd/MM/yyyy',
);
const _slotHeight = 16.0;
final _date = DateTime(2026, 9, 9);

final _workBlock = TimeObject(
  id: '1',
  title: 'Work',
  start: DateTime(2026, 9, 9, 9),
  end: DateTime(2026, 9, 9, 10),
  kind: BlockKind.anchor,
  locked: false,
);

Future<void> _pump(
  WidgetTester tester, {
  Set<String> highlightedBlockIds = const {},
  List<TemplateApplyGhost> ghosts = const [],
  void Function(String)? onHighlightAnimationEnd,
  void Function(int)? onGhostAnimationEnd,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: ProviderContainer(),
    child: MaterialApp(
      home: Scaffold(
        body: DayGrid(
          key: scheduleGridKeyFor(DayColumn(_date)),
          date: _date,
          column: DayColumn(_date),
          controller: const DayScheduleController(),
          actions: dayScheduleBlockActions,
          blocks: [_workBlock],
          settings: _settings,
          slotHeight: _slotHeight,
          highlightedBlockIds: highlightedBlockIds,
          ghosts: ghosts,
          onHighlightAnimationEnd: onHighlightAnimationEnd ?? (_) {},
          onGhostAnimationEnd: onGhostAnimationEnd ?? (_) {},
          onCreateBlock: ({required start, required end, required kind}) {},
        ),
      ),
    ),
  ),
);

void main() {
  group('DayGrid template-apply effects', () {
    testWidgets(
      'renders a highlight for a highlighted block and reports when its '
      'animation ends',
      (tester) async {
        String? endedId;
        await _pump(
          tester,
          highlightedBlockIds: {_workBlock.id},
          onHighlightAnimationEnd: (id) => endedId = id,
        );

        expect(
          find.byKey(Key('day-grid-highlight-${_workBlock.id}')),
          findsOneWidget,
        );

        await tester.pumpAndSettle();

        expect(endedId, _workBlock.id);
      },
    );

    testWidgets('renders no highlight when no block is highlighted', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.byKey(Key('day-grid-highlight-${_workBlock.id}')),
        findsNothing,
      );
    });

    testWidgets(
      'renders a ghost for a skipped range and reports when its animation '
      'ends',
      (tester) async {
        int? endedId;
        final ghost = TemplateApplyGhost(
          id: 7,
          start: DateTime(2026, 9, 9, 14),
          end: DateTime(2026, 9, 9, 15),
        );

        await _pump(
          tester,
          ghosts: [ghost],
          onGhostAnimationEnd: (id) => endedId = id,
        );

        expect(find.byKey(const Key('day-grid-ghost-7')), findsOneWidget);

        await tester.pumpAndSettle();

        expect(endedId, 7);
      },
    );
  });
}
