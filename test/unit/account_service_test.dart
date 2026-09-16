import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/account_service.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';

void main() {
  test('logout clears every synced store, every sync cursor, and the '
      'session, but leaves unrelated settings alone', () async {
    final db = await newDatabaseFactoryMemory().openDatabase('test.db');
    final settings = SembastAppSettingsRepository(db);
    final client = PocketBaseSyncClient(
      baseUrl: 'http://localhost:8090',
      settings: settings,
    );

    // Seed data in every synced store, a couple of sync cursors, a
    // session, and one unrelated setting.
    await tasksStore.record('t1').put(db, {'id': 't1', 'title': 'x'});
    await categoriesStore.record('c1').put(db, {'id': 'c1', 'name': 'x'});
    await templatesStore.record('tpl1').put(db, {'id': 'tpl1'});
    await templateBlocksStore.record('tb1').put(db, {'id': 'tb1'});
    await savedSearchesStore.record('s1').put(db, {'id': 's1'});
    await dayBlocksStore.record('d1').put(db, {'id': 'd1'});
    await settings.setValue('sync_push_tasks', '2026-01-01T00:00:00.000Z');
    await settings.setValue('sync_pull_tasks', '2026-01-01T00:00:00.000Z');
    await settings.setValue('account_identity', 'me@example.com');
    await settings.setValue('account_token', 'a-token');
    await settings.setInstallHintDismissedAt(DateTime(2026, 1, 1));

    await logout(db: db, settings: settings, client: client);

    expect(await tasksStore.record('t1').get(db), isNull);
    expect(await categoriesStore.record('c1').get(db), isNull);
    expect(await templatesStore.record('tpl1').get(db), isNull);
    expect(await templateBlocksStore.record('tb1').get(db), isNull);
    expect(await savedSearchesStore.record('s1').get(db), isNull);
    expect(await dayBlocksStore.record('d1').get(db), isNull);
    expect(await settings.getValue('sync_push_tasks'), isNull);
    expect(await settings.getValue('sync_pull_tasks'), isNull);
    expect(await settings.getValue('account_identity'), isNull);
    expect(await settings.getValue('account_token'), isNull);
    expect(await settings.getInstallHintDismissedAt(), DateTime(2026, 1, 1));
  });
}
