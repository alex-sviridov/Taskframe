import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';

void main() {
  group('InMemoryAppSettingsRepository', () {
    test('getInstallHintDismissedAt starts null', () async {
      final repository = InMemoryAppSettingsRepository();
      expect(await repository.getInstallHintDismissedAt(), isNull);
    });

    test('setInstallHintDismissedAt is read back by get', () async {
      final repository = InMemoryAppSettingsRepository();
      final time = DateTime(2030);

      await repository.setInstallHintDismissedAt(time);

      expect(await repository.getInstallHintDismissedAt(), time);
    });

    test('getValue returns null for an unset key', () async {
      final repository = InMemoryAppSettingsRepository();
      expect(await repository.getValue('missing'), isNull);
    });

    test('setValue then getValue round-trips', () async {
      final repository = InMemoryAppSettingsRepository();
      await repository.setValue('sync_pull_tasks', '2026-09-15T00:00:00.000Z');
      expect(
        await repository.getValue('sync_pull_tasks'),
        '2026-09-15T00:00:00.000Z',
      );
    });

    test('deleteValue removes a previously-set value', () async {
      final repository = InMemoryAppSettingsRepository();
      await repository.setValue('sync_pull_tasks', '2026-09-15T00:00:00.000Z');

      await repository.deleteValue('sync_pull_tasks');

      expect(await repository.getValue('sync_pull_tasks'), isNull);
    });

    test('deleteValue on an unset key is a no-op', () async {
      final repository = InMemoryAppSettingsRepository();
      await repository.deleteValue('missing'); // should not throw
      expect(await repository.getValue('missing'), isNull);
    });
  });

  group('SembastAppSettingsRepository', () {
    late SembastAppSettingsRepository repository;

    setUp(() async {
      final db = await newDatabaseFactoryMemory().openDatabase('test.db');
      repository = SembastAppSettingsRepository(db);
    });

    test('getInstallHintDismissedAt starts null', () async {
      expect(await repository.getInstallHintDismissedAt(), isNull);
    });

    test('setInstallHintDismissedAt is read back by get', () async {
      final time = DateTime(2030, 1, 1, 12, 30);

      await repository.setInstallHintDismissedAt(time);

      expect(await repository.getInstallHintDismissedAt(), time);
    });

    test('getValue returns null for an unset key', () async {
      expect(await repository.getValue('missing'), isNull);
    });

    test('setValue then getValue round-trips', () async {
      await repository.setValue('sync_pull_tasks', '2026-09-15T00:00:00.000Z');
      expect(
        await repository.getValue('sync_pull_tasks'),
        '2026-09-15T00:00:00.000Z',
      );
    });

    test('deleteValue removes a previously-set value', () async {
      await repository.setValue('sync_pull_tasks', '2026-09-15T00:00:00.000Z');

      await repository.deleteValue('sync_pull_tasks');

      expect(await repository.getValue('sync_pull_tasks'), isNull);
    });

    test('deleteValue on an unset key is a no-op', () async {
      await repository.deleteValue('missing'); // should not throw
      expect(await repository.getValue('missing'), isNull);
    });
  });
}
