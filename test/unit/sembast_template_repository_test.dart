import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/features/day/models/time_object.dart';
import 'package:taskframe/features/template/data/sembast_template_repository.dart';
import 'package:taskframe/features/template/models/template.dart';

void main() {
  group('SembastTemplateRepository', () {
    late SembastTemplateRepository repository;
    late Database db;

    setUp(() async {
      db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastTemplateRepository(db);
    });

    test('load starts empty', () async {
      expect(await repository.load(), isEmpty);
    });

    test('add appends a template with the given name', () async {
      final added = await repository.add(name: 'Weekday');

      expect(added.name, 'Weekday');
      expect(await repository.load(), [added]);
    });

    test('add assigns distinct ids to successive templates', () async {
      final first = await repository.add(name: 'A');
      final second = await repository.add(name: 'B');

      expect(first.id, isNot(second.id));
    });

    test('templates load back in creation order', () async {
      await repository.add(name: 'First');
      await repository.add(name: 'Second');

      final templates = await repository.load();

      expect(templates[0].name, 'First');
      expect(templates[1].name, 'Second');
    });

    test("rename updates the template's name", () async {
      final added = await repository.add(name: 'Weekday');

      final renamed = await repository.rename(added, name: 'Renamed');

      expect(renamed.id, added.id);
      expect((await repository.load()).single.name, 'Renamed');
    });

    test('rename throws StateError if the template is not found', () async {
      final missing = Template(id: 't-missing', name: 'Weekday');

      expect(
        () => repository.rename(missing, name: 'Renamed'),
        throwsA(isA<StateError>()),
      );
    });

    test('delete removes the template', () async {
      final added = await repository.add(name: 'Weekday');

      await repository.delete(added);

      expect(await repository.load(), isEmpty);
    });

    test('delete soft-deletes: record stays but is excluded from load', () async {
      final added = await repository.add(name: 'Weekday');

      await repository.delete(added);

      expect(await repository.load(), isEmpty);
      final record = await templatesStore.record(added.id).get(db);
      expect(record!['deleted'], isTrue);
    });
  });

  group('SembastTemplateBlocksRepository', () {
    late SembastTemplateBlocksRepository repository;
    late Database db;

    setUp(() async {
      db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastTemplateBlocksRepository(db);
    });

    test('load starts empty for a fresh templateId', () async {
      expect(await repository.load('t1'), isEmpty);
    });

    test('add appends a block for the given templateId', () async {
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
      await repository.add(
        't1',
        start: DateTime(2000, 1, 1, 9),
        end: DateTime(2000, 1, 1, 9, 30),
        kind: BlockKind.anchor,
      );

      expect(await repository.load('t2'), isEmpty);
    });

    test('move moves a block from one templateId to another', () async {
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

    test('delete soft-deletes: block stays in the store but excluded from '
        'load', () async {
      final added = await repository.add(
        'tpl1',
        start: DateTime(2026, 1, 1, 9),
        end: DateTime(2026, 1, 1, 10),
        kind: BlockKind.frame,
      );

      await repository.delete(added, templateId: 'tpl1');

      expect(await repository.load('tpl1'), isEmpty);
      final record = await templateBlocksStore.record(added.id).get(db);
      expect(record!['deleted'], isTrue);
    });
  });
}
