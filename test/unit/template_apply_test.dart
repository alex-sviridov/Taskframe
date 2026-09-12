import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/day/models/schedule_column.dart';
import 'package:taskframe/features/day/template_apply.dart';

TimeObject _block({
  required String id,
  required DateTime start,
  required DateTime end,
  String title = 'Block',
  BlockKind kind = BlockKind.anchor,
  String categoryId = 'default',
}) => TimeObject(
  id: id,
  title: title,
  start: start,
  end: end,
  kind: kind,
  locked: false,
  categoryId: categoryId,
);

void main() {
  final date = DateTime(2026, 9, 14);

  test('rebases every non-overlapping template block onto the target date', () {
    final templateBlocks = [
      _block(
        id: 't1',
        title: 'Breakfast',
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
        categoryId: 'food',
      ),
    ];

    final result = resolveTemplateApply(
      templateBlocks: templateBlocks,
      dayBlocks: const [],
      date: date,
    );

    expect(result.skipped, isEmpty);
    expect(result.toAdd, hasLength(1));
    final added = result.toAdd.single;
    expect(added.start, DateTime(2026, 9, 14, 8));
    expect(added.end, DateTime(2026, 9, 14, 9));
    expect(added.title, 'Breakfast');
    expect(added.categoryId, 'food');
  });

  test('skips a template block that overlaps an existing day block', () {
    final templateBlocks = [
      _block(
        id: 't1',
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
      ),
    ];
    final dayBlocks = [
      _block(
        id: 'd1',
        start: DateTime(2026, 9, 14, 8, 30),
        end: DateTime(2026, 9, 14, 9, 30),
      ),
    ];

    final result = resolveTemplateApply(
      templateBlocks: templateBlocks,
      dayBlocks: dayBlocks,
      date: date,
    );

    expect(result.toAdd, isEmpty);
    expect(result.skipped, [
      (start: DateTime(2026, 9, 14, 8), end: DateTime(2026, 9, 14, 9)),
    ]);
  });

  test(
    'adds non-overlapping blocks while skipping only the conflicting one',
    () {
      final templateBlocks = [
        _block(
          id: 't1',
          title: 'Free',
          start: DateTime(
            templateAnchorDate.year,
            templateAnchorDate.month,
            templateAnchorDate.day,
            7,
          ),
          end: DateTime(
            templateAnchorDate.year,
            templateAnchorDate.month,
            templateAnchorDate.day,
            8,
          ),
        ),
        _block(
          id: 't2',
          title: 'Conflicting',
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
        ),
      ];
      final dayBlocks = [
        _block(
          id: 'd1',
          start: DateTime(2026, 9, 14, 8, 30),
          end: DateTime(2026, 9, 14, 9, 30),
        ),
      ];

      final result = resolveTemplateApply(
        templateBlocks: templateBlocks,
        dayBlocks: dayBlocks,
        date: date,
      );

      expect(result.toAdd.map((b) => b.title), ['Free']);
      expect(result.skipped, [
        (start: DateTime(2026, 9, 14, 8), end: DateTime(2026, 9, 14, 9)),
      ]);
    },
  );

  test('skips a template block that would overlap another already-accepted template block', () {
    final templateBlocks = [
      _block(
        id: 't1',
        title: 'First',
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
      ),
      _block(
        id: 't2',
        title: 'Overlapping',
        start: DateTime(
          templateAnchorDate.year,
          templateAnchorDate.month,
          templateAnchorDate.day,
          8,
          30,
        ),
        end: DateTime(
          templateAnchorDate.year,
          templateAnchorDate.month,
          templateAnchorDate.day,
          9,
          30,
        ),
      ),
    ];

    final result = resolveTemplateApply(
      templateBlocks: templateBlocks,
      dayBlocks: const [],
      date: date,
    );

    expect(result.toAdd.map((b) => b.title), ['First']);
    expect(result.skipped, [
      (start: DateTime(2026, 9, 14, 8, 30), end: DateTime(2026, 9, 14, 9, 30)),
    ]);
  });
}
