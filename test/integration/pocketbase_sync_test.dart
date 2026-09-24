// test/integration/pocketbase_sync_test.dart
//
// Requires a local PocketBase with collections already set up — see
// `make integration-test`. Skipped by `make check`/`make test`, which
// only run test/unit and test/widget.
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:taskframe/core/storage/app_database.dart';
import 'package:taskframe/core/storage/app_settings_repository.dart';
import 'package:taskframe/core/sync/account_service.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_collection.dart';
import 'package:taskframe/core/sync/sync_engine.dart';

void main() {
  group('PocketBase sync (requires a local server)', () {
    late Database deviceADb;
    late Database deviceBDb;
    late AppSettingsRepository deviceASettings;
    late AppSettingsRepository deviceBSettings;
    late PocketBaseSyncClient deviceAClient;
    late PocketBaseSyncClient deviceBClient;
    late SyncEngine deviceAEngine;
    late SyncEngine deviceBEngine;

    setUp(() async {
      deviceADb = await newDatabaseFactoryMemory().openDatabase('a.db');
      deviceBDb = await newDatabaseFactoryMemory().openDatabase('b.db');
      deviceASettings = InMemoryAppSettingsRepository();
      deviceBSettings = InMemoryAppSettingsRepository();
      deviceAClient = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: deviceASettings,
      );
      deviceBClient = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: deviceBSettings,
      );
      deviceAEngine = SyncEngine(
        db: deviceADb,
        settings: deviceASettings,
        backend: deviceAClient,
      );
      deviceBEngine = SyncEngine(
        db: deviceBDb,
        settings: deviceBSettings,
        backend: deviceBClient,
      );
    });

    test('an edit on device A appears on device B after pairing', () async {
      final email =
          'edit-propagation-'
          '${DateTime.now().microsecondsSinceEpoch}@test.local';
      await deviceAClient.register(email, 'testpass123');
      await deviceBClient.login(email, 'testpass123');

      await tasksStore.record('t1').put(deviceADb, {
        'id': 't1',
        'title': 'Buy milk',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });

      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      final onB = await tasksStore.record('t1').get(deviceBDb);
      expect(onB!['title'], 'Buy milk');
    });

    test('a delete on device A propagates to device B', () async {
      final email =
          'delete-propagation-'
          '${DateTime.now().microsecondsSinceEpoch}@test.local';
      await deviceAClient.register(email, 'testpass123');
      await deviceBClient.login(email, 'testpass123');

      await tasksStore.record('t2').put(deviceADb, {
        'id': 't2',
        'title': 'Temp',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });
      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      await tasksStore.record('t2').put(deviceADb, {
        'id': 't2',
        'title': 'Temp',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': true,
      });
      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      final onB = await tasksStore.record('t2').get(deviceBDb);
      expect(onB!['deleted'], isTrue);
    });

    test('concurrent edits resolve to the newer updatedAt', () async {
      final email =
          'concurrent-edits-'
          '${DateTime.now().microsecondsSinceEpoch}@test.local';
      await deviceAClient.register(email, 'testpass123');
      await deviceBClient.login(email, 'testpass123');

      final base = DateTime.now().toUtc();
      await tasksStore.record('t3').put(deviceADb, {
        'id': 't3',
        'title': 'From A',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': base.toIso8601String(),
        'deleted': false,
      });
      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);

      await tasksStore.record('t3').put(deviceADb, {
        'id': 't3',
        'title': 'Older edit from A',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': base.add(const Duration(seconds: 1)).toIso8601String(),
        'deleted': false,
      });
      await tasksStore.record('t3').put(deviceBDb, {
        'id': 't3',
        'title': 'Newer edit from B',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': base.add(const Duration(seconds: 5)).toIso8601String(),
        'deleted': false,
      });

      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBEngine.syncAll([_tasksCollection]);
      await deviceAEngine.syncAll([_tasksCollection]);

      final onA = await tasksStore.record('t3').get(deviceADb);
      expect(onA!['title'], 'Newer edit from B');
    });

    test('registering uploads data created while in guest mode', () async {
      await tasksStore.record('guest1').put(deviceADb, {
        'id': 'guest1',
        'title': 'Created as a guest',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });

      // Guest mode: syncing before any account exists is a no-op (throws,
      // swallowed by SyncEngine, retried later) - the record stays local.
      await deviceAEngine.syncAll([_tasksCollection]);

      final email =
          'guest-register-${DateTime.now().microsecondsSinceEpoch}@test.local';
      await deviceAClient.register(email, 'testpass123');
      await deviceAEngine.syncAll([_tasksCollection]);
      await deviceBClient.login(email, 'testpass123');
      await deviceBEngine.syncAll([_tasksCollection]);

      final onB = await tasksStore.record('guest1').get(deviceBDb);
      expect(onB!['title'], 'Created as a guest');
    });

    test('logging into an existing account merges local guest data with the '
        "account's existing data (the raw PocketBaseSyncClient + SyncEngine "
        'mechanism — the app-level login flow deliberately avoids this by '
        'wiping guest data first; see loginDroppingGuestData() in '
        'account_service.dart)', () async {
      final email = 'merge-${DateTime.now().microsecondsSinceEpoch}@test.local';

      // Device A registers and syncs one record - this account now has
      // remote data.
      await deviceAClient.register(email, 'testpass123');
      await tasksStore.record('fromA').put(deviceADb, {
        'id': 'fromA',
        'title': 'From device A',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });
      await deviceAEngine.syncAll([_tasksCollection]);

      // Device B has its own local guest record, then logs into the same
      // (already-populated) account.
      await tasksStore.record('fromBGuest').put(deviceBDb, {
        'id': 'fromBGuest',
        'title': 'From device B, created as a guest',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });
      await deviceBClient.login(email, 'testpass123');
      await deviceBEngine.syncAll([_tasksCollection]);

      // Device B should now have both records.
      expect(
        (await tasksStore.record('fromA').get(deviceBDb))!['title'],
        'From device A',
      );
      expect(
        (await tasksStore.record('fromBGuest').get(deviceBDb))!['title'],
        'From device B, created as a guest',
      );

      // And device A, after another sync, should see device B's guest
      // record too.
      await deviceAEngine.syncAll([_tasksCollection]);
      expect(
        (await tasksStore.record('fromBGuest').get(deviceADb))!['title'],
        'From device B, created as a guest',
      );
    });

    test('logout clears local data and a later login re-pulls it', () async {
      final email =
          'logout-${DateTime.now().microsecondsSinceEpoch}@test.local';
      await deviceAClient.register(email, 'testpass123');
      await tasksStore.record('persisted').put(deviceADb, {
        'id': 'persisted',
        'title': 'Should survive logout on the server',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });
      await deviceAEngine.syncAll([_tasksCollection]);

      await logout(
        db: deviceADb,
        settings: deviceASettings,
        client: deviceAClient,
        syncEngine: deviceAEngine,
      );

      expect(await tasksStore.record('persisted').get(deviceADb), isNull);

      await deviceAClient.login(email, 'testpass123');
      await deviceAEngine.syncAll([_tasksCollection]);

      final onA = await tasksStore.record('persisted').get(deviceADb);
      expect(onA!['title'], 'Should survive logout on the server');
    });

    test('logout then registering/syncing a DIFFERENT account on the same '
        "device doesn't leak the first account's data", () async {
      final emailA =
          'switch-a-${DateTime.now().microsecondsSinceEpoch}@test.local';
      final emailB =
          'switch-b-${DateTime.now().microsecondsSinceEpoch}@test.local';

      // Account 1, on device A: register, create+sync a record.
      await deviceAClient.register(emailA, 'testpass123');
      await tasksStore.record('acct1task').put(deviceADb, {
        'id': 'acct1task',
        'title': 'Belongs to account 1',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });
      await deviceAEngine.syncAll([_tasksCollection]);
      expect(await tasksStore.record('acct1task').get(deviceADb), isNotNull);

      // Explicit logout on device A.
      await logout(
        db: deviceADb,
        settings: deviceASettings,
        client: deviceAClient,
        syncEngine: deviceAEngine,
      );
      expect(await tasksStore.record('acct1task').get(deviceADb), isNull);

      // Account 2, same device: register (a brand-new, unrelated
      // account) and create+sync its own record.
      await deviceAClient.register(emailB, 'testpass123');
      await tasksStore.record('acct2task').put(deviceADb, {
        'id': 'acct2task',
        'title': 'Belongs to account 2',
        'closed': false,
        'categoryId': '0',
        'tags': <String>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'deleted': false,
      });
      await deviceAEngine.syncAll([_tasksCollection]);

      // Account 1's record must not have resurfaced locally, and must
      // not be visible to account 2 anywhere (it was never pushed
      // under account 2's owner).
      expect(await tasksStore.record('acct1task').get(deviceADb), isNull);
      expect(
        (await tasksStore.record('acct2task').get(deviceADb))!['title'],
        'Belongs to account 2',
      );

      // Confirm from a second device logged into account 2: only
      // account 2's data should ever reach it.
      await deviceBClient.login(emailB, 'testpass123');
      await deviceBEngine.syncAll([_tasksCollection]);
      expect(await tasksStore.record('acct1task').get(deviceBDb), isNull);
      expect(
        (await tasksStore.record('acct2task').get(deviceBDb))!['title'],
        'Belongs to account 2',
      );

      // And logging back into account 1 (a third client, since A/B are
      // now on account 2) still sees its own data server-side,
      // confirming nothing was destroyed remotely - only wiped
      // locally.
      final deviceCDb = await newDatabaseFactoryMemory().openDatabase('c.db');
      final deviceCSettings = InMemoryAppSettingsRepository();
      final deviceCClient = PocketBaseSyncClient(
        baseUrl: 'http://localhost:8090',
        settings: deviceCSettings,
      );
      final deviceCEngine = SyncEngine(
        db: deviceCDb,
        settings: deviceCSettings,
        backend: deviceCClient,
      );
      await deviceCClient.login(emailA, 'testpass123');
      await deviceCEngine.syncAll([_tasksCollection]);
      expect(
        (await tasksStore.record('acct1task').get(deviceCDb))!['title'],
        'Belongs to account 1',
      );
      expect(await tasksStore.record('acct2task').get(deviceCDb), isNull);
    });
  });
}

final _tasksCollection = SyncCollection(name: 'tasks', store: tasksStore);
