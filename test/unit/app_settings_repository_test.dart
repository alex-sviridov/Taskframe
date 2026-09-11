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
      final time = DateTime(2030, 1, 1);

      await repository.setInstallHintDismissedAt(time);

      expect(await repository.getInstallHintDismissedAt(), time);
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
  });
}
