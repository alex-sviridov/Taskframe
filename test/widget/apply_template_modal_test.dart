import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/providers.dart';
import 'package:taskframe/features/day/template_apply_effects.dart';
import 'package:taskframe/features/day/widgets/apply_template_modal.dart';
import 'package:taskframe/features/template/models/template.dart';
import 'package:taskframe/features/template/providers.dart';

// Fixed, far-past date: InMemoryDayBlocksRepository seeds hardcoded blocks
// for whatever date happens to be the real wall-clock "today", matching
// the convention in block_edit_modal_test.dart.
final _date = DateTime(2000);

Future<(ProviderContainer, Template)> _seededContainer() async {
  final container = ProviderContainer();
  await container.read(dayBlocksProvider(_date).future);
  final template = await container
      .read(templateListProvider.notifier)
      .addTemplate(name: 'Morning');
  await container
      .read(templateBlocksProvider(template.id).notifier)
      .addBlock(
        start: DateTime(
          templateAnchorDate.year,
          templateAnchorDate.month,
          templateAnchorDate.day,
          8,
        ),
        end: DateTime(
          templateAnchorDate.year,
          templateAnchorDate.month,
          templateAnchorDate.day,
          9,
        ),
        kind: BlockKind.anchor,
        title: 'Breakfast',
      );
  return (container, template);
}

Future<void> _pumpOpenButton(
  WidgetTester tester,
  ProviderContainer container,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showApplyTemplateModal(context: context, date: _date),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('ApplyTemplateModal', () {
    testWidgets('lists templates by name', (tester) async {
      final (container, template) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text(template.name), findsOneWidget);
    });

    testWidgets('tapping a template applies its blocks to the day and closes', (
      tester,
    ) async {
      final (container, template) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(template.name));
      await tester.pumpAndSettle();

      expect(find.text(template.name), findsNothing);
      final dayBlocks = container.read(dayBlocksProvider(_date)).value!;
      expect(dayBlocks.map((b) => b.title), contains('Breakfast'));
    });

    testWidgets('highlights the newly added block after applying', (
      tester,
    ) async {
      final (container, template) = await _seededContainer();
      addTearDown(container.dispose);
      await _pumpOpenButton(tester, container);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(template.name));
      await tester.pumpAndSettle();

      final addedId = container.read(dayBlocksProvider(_date)).value!.single.id;
      expect(
        container.read(templateApplyEffectsProvider(_date)).highlightedIds,
        {addedId},
      );
    });
  });
}
