import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/template/data/template_repository.dart';
import 'package:taskframe/features/template/models/template.dart';

void main() {
  group('InMemoryTemplateRepository', () {
    test('load starts empty', () async {
      final repository = InMemoryTemplateRepository();
      expect(await repository.load(), isEmpty);
    });

    test('add appends a template with the given name', () async {
      final repository = InMemoryTemplateRepository();
      final added = await repository.add(name: 'Weekday');
      expect(added.name, 'Weekday');
      expect(await repository.load(), [added]);
    });

    test("rename updates the template's name", () async {
      final repository = InMemoryTemplateRepository();
      final added = await repository.add(name: 'Weekday');
      final renamed = await repository.rename(added, name: 'Renamed');
      expect(renamed.id, added.id);
      expect((await repository.load()).single.name, 'Renamed');
    });

    test('rename throws StateError if template not found', () async {
      final repository = InMemoryTemplateRepository();
      final missingTemplate = Template(id: 't-missing', name: 'Weekday');
      expect(
        () => repository.rename(missingTemplate, name: 'Renamed'),
        throwsA(isA<StateError>()),
      );
    });

    test('delete removes the template', () async {
      final repository = InMemoryTemplateRepository();
      final added = await repository.add(name: 'Weekday');
      await repository.delete(added);
      expect(await repository.load(), isEmpty);
    });

    test('add assigns distinct ids to successive templates', () async {
      final repository = InMemoryTemplateRepository();
      final first = await repository.add(name: 'A');
      final second = await repository.add(name: 'B');
      expect(first.id, isNot(second.id));
    });
  });

  group('InMemoryTemplateBlocksRepository', () {
    test('load starts empty for a fresh templateId', () async {
      final repository = InMemoryTemplateBlocksRepository();
      expect(await repository.load('t1'), isEmpty);
    });

    test('add appends a block for the given templateId', () async {
      final repository = InMemoryTemplateBlocksRepository();
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
        title: 'Standup',
      );
      expect(added.title, 'Standup');
      final blocks = await repository.load('t1');
      expect(blocks.single.id, added.id);
    });

    test('a block added to one templateId is invisible to another', () async {
      final repository = InMemoryTemplateBlocksRepository();
      await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );
      expect(await repository.load('t2'), isEmpty);
    });

    test('move moves a block from one templateId to another', () async {
      final repository = InMemoryTemplateBlocksRepository();
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      await repository.move(
        added,
        fromTemplateId: 't1',
        toTemplateId: 't2',
        newStart: DateTime(2000, 1, 1, 14),
        newEnd: DateTime(2000, 1, 1, 14, 30),
      );

      expect(await repository.load('t1'), isEmpty);
      final moved = (await repository.load('t2')).single;
      expect(moved.id, added.id);
      expect(moved.start, DateTime(2000, 1, 1, 14));
    });

    test('update persists a title change', () async {
      final repository = InMemoryTemplateBlocksRepository();
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      await repository.update(added, templateId: 't1', title: 'Renamed');

      final updated = (await repository.load('t1')).single;
      expect(updated.title, 'Renamed');
    });

    test('delete removes the block', () async {
      final repository = InMemoryTemplateBlocksRepository();
      final added = await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      await repository.delete(added, templateId: 't1');

      expect(await repository.load('t1'), isEmpty);
    });

    test('deleteAll clears one templateId without touching another', () async {
      final repository = InMemoryTemplateBlocksRepository();
      for (final templateId in ['t1', 't2']) {
        await repository.add(
          templateId,
          start: DateTime(2000, 1, 1, 9),
          end: DateTime(2000, 1, 1, 9, 30),
          kind: BlockKind.anchor,
        );
      }

      await repository.deleteAll('t1');

      expect(await repository.load('t1'), isEmpty);
      expect(await repository.load('t2'), hasLength(1));
    });
  });
}
