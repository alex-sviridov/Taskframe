// lib/features/account/account_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskframe/core/platform/pocketbase_base_url.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';
import 'package:taskframe/core/sync/sync_status.dart';
import 'package:taskframe/features/category/providers.dart';
import 'package:taskframe/features/day/day_blocks_provider.dart';
import 'package:taskframe/features/saved_search/providers.dart';
import 'package:taskframe/features/task/providers.dart';
import 'package:taskframe/features/template/providers.dart';

/// Backs [syncStatusProvider] — `main.dart` writes to [current] from
/// `startSyncTriggers`'s `onStatusChanged` callback.
class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus.idle;

  /// The latest reported [SyncStatus].
  SyncStatus get current => state;

  set current(SyncStatus status) => state = status;
}

/// This device's current [SyncStatus] — updated by `main.dart` wiring
/// `startSyncTriggers`'s `onStatusChanged` callback into this provider.
/// Meaningless while [accountProvider]'s email is `null` (guest mode):
/// see [SyncStatus]'s doc comment.
final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);

const _pocketBaseBaseUrlOverride = String.fromEnvironment('POCKETBASE_URL');

/// Picks the PocketBase client's base URL: [override] (the raw
/// `--dart-define=POCKETBASE_URL=...` value, empty when unset) wins when
/// given; otherwise falls back to calling [defaultUrl]. Split out from
/// [pocketBaseBaseUrl] so the precedence logic is testable without a
/// browser.
String resolvePocketBaseBaseUrl({
  required String override,
  required String Function() defaultUrl,
}) => override.isNotEmpty ? override : defaultUrl();

/// The PocketBase base URL. Defaults to the page's own `<base href>` on
/// web (same-origin, whatever prefix the app is actually served under —
/// see [defaultPocketBaseBaseUrl]) — nginx (`nginx.conf`) proxies `/api/`
/// under that same prefix to the `pocketbase` service, so the web app
/// never needs to know PocketBase's real host. Override at build time
/// with `--dart-define=POCKETBASE_URL=...` for a deployment where the app
/// isn't served through that proxy (e.g. a native build talking to a
/// PocketBase host directly).
final String pocketBaseBaseUrl = resolvePocketBaseBaseUrl(
  override: _pocketBaseBaseUrlOverride,
  defaultUrl: defaultPocketBaseBaseUrl,
);

/// Riverpod-accessible form of [pocketBaseBaseUrl], for widgets/tests.
final pocketBaseBaseUrlProvider = Provider<String>((ref) => pocketBaseBaseUrl);

/// The app's single [PocketBaseSyncClient]. Thrown by default; overridden
/// at the composition root (`main.dart`) once the real database/settings
/// it needs are available.
final pocketBaseSyncClientProvider = Provider<PocketBaseSyncClient>((ref) {
  throw UnimplementedError(
    'Override with a PocketBaseSyncClient built from '
    'appSettingsRepositoryProvider at the composition root — see '
    'sembastOverrides in main.dart.',
  );
});

/// Runs the full "return to guest mode" flow (`logout()` in
/// `account_service.dart`, which needs the raw `Database` this provider
/// doesn't have direct access to). Overridden at the composition root,
/// where that database is available — see `main.dart`.
final accountLogoutProvider = Provider<Future<void> Function()>((ref) {
  throw UnimplementedError(
    'Override with a closure calling logout(...) at the composition root '
    '— see main.dart.',
  );
});

/// Every provider that caches a list/family read from one of the six
/// synced sembast stores, keyed by the `SyncCollection.name` it's backed
/// by. Invalidating one after a mutation to local storage that didn't
/// originate from the provider's own repository calls (a logout/
/// account-switch wipe, or a background sync pull — see
/// `sync_trigger.dart`'s `onSynced`) is what makes that mutation visible
/// in the already-running UI instead of staying invisible until a full
/// reload rebuilds every provider from scratch.
// The value type here is Riverpod's `ProviderOrFamily`, which isn't
// exported from `package:flutter_riverpod` for us to name explicitly —
// left uninferred rather than referencing an internal `package:riverpod`
// path.
// ignore: specify_nonobvious_property_types
final syncedProvidersByCollection = {
  'tasks': taskListProvider,
  'categories': categoryListProvider,
  'saved_searches': savedSearchListProvider,
  'templates': templateListProvider,
  'template_blocks': templateBlocksProvider,
  'day_blocks': dayBlocksProvider,
};

/// This device's account state: the logged-in email, or `null` for guest
/// mode.
class AccountState {
  /// Creates an [AccountState].
  const new({required this.email, this.sessionExpired = false});

  /// The logged-in account's email, or `null` for guest mode.
  final String? email;

  /// True when [email] is non-null but the stored session was rejected
  /// by the server (not just unreachable) — see
  /// [SessionRestoreResult.expired]. Sync will keep failing silently
  /// until this identity logs in again, so the UI must prompt for that
  /// rather than showing a plain "logged in" state.
  final bool sessionExpired;
}

/// This device's account state — see [AccountState]. Also exposes the
/// actions to register/log in/log out.
class AccountNotifier extends AsyncNotifier<AccountState> {
  @override
  Future<AccountState> build() async {
    final client = ref.watch(pocketBaseSyncClientProvider);
    // `restoreSession()`'s `offline` result means the refresh couldn't be
    // verified due to a network failure — not a rejection by the server
    // — so the stored identity should still be treated as logged in.
    // Gating the returned identity on that would show an already-logged-
    // in offline user a blank guest register/login form. `currentEmail()`
    // reads the stored identity key regardless of the refresh outcome,
    // so use that as the source of truth for "am I logged in", and only
    // `expired` (a genuine server rejection) flips [sessionExpired].
    final result = await client.restoreSession();
    final email = await client.currentEmail();
    return AccountState(
      email: email,
      sessionExpired: email != null && result == SessionRestoreResult.expired,
    );
  }

  /// Registers a new account, uploading any local guest data to it on
  /// the next sync (no separate migration step — see the design doc).
  Future<void> register(String email, String password) async {
    await _wipeIfSwitchingIdentity(email);
    await ref.read(pocketBaseSyncClientProvider).register(email, password);
    state = AsyncData(AccountState(email: email));
  }

  /// Logs into an existing account, merging local guest data into it on
  /// the next sync. Also used to re-authenticate after
  /// [AccountState.sessionExpired] — same identity, so
  /// [_wipeIfSwitchingIdentity] is a no-op in that case.
  Future<void> login(String email, String password) async {
    await _wipeIfSwitchingIdentity(email);
    await ref.read(pocketBaseSyncClientProvider).login(email, password);
    state = AsyncData(AccountState(email: email));
  }

  /// If a *different* identity than [email] is currently stored (i.e.
  /// this device is about to switch accounts without an explicit logout
  /// first — e.g. a stale/offline session was shown but the user chooses
  /// to register/login as someone else anyway), wipes local synced
  /// data/cursors/session for the old identity first. Without this, the
  /// old account's data would stay local and any edits made since its
  /// last push cursor would upload into the new account on the next
  /// sync — a real cross-account data leak, not just a stale-UI issue.
  /// A no-op in the normal case (guest -> account, or re-logging into the
  /// same already-stored identity).
  Future<void> _wipeIfSwitchingIdentity(String email) async {
    final client = ref.read(pocketBaseSyncClientProvider);
    final current = await client.currentEmail();
    if (current != null && current != email) {
      await ref.read(accountLogoutProvider)();
      _invalidateSyncedProviders();
    }
  }

  /// Returns to guest mode: clears local synced data/cursors/session.
  Future<void> logout() async {
    await ref.read(accountLogoutProvider)();
    _invalidateSyncedProviders();
    state = const AsyncData(AccountState(email: null));
  }

  /// Invalidates every provider that caches data read from one of the
  /// six synced sembast stores, so each re-reads (now-empty) storage on
  /// next access instead of continuing to show the just-logged-out (or
  /// just-switched-from) account's data from stale in-memory state.
  /// Without this, an edit made against that stale state would call
  /// `repository.update()`, which re-`put`s the record straight back
  /// into the store this just wiped — silently resurrecting it, ready to
  /// upload into whatever account logs in next.
  ///
  /// The repository providers themselves (`taskRepositoryProvider` etc.)
  /// are wired via `overrideWithValue` in `main.dart` and never change,
  /// so invalidating them wouldn't help — it's the *notifier* providers
  /// that cache a loaded-once list that need invalidating.
  /// `ref.invalidate(familyProvider)` with no argument invalidates every
  /// instantiated member of a family, which is what's needed for
  /// `dayBlocksProvider`/`templateBlocksProvider`.
  void _invalidateSyncedProviders() {
    syncedProvidersByCollection.values.forEach(ref.invalidate);
  }
}

/// This device's account state — see [AccountNotifier].
final accountProvider = AsyncNotifierProvider<AccountNotifier, AccountState>(
  AccountNotifier.new,
);
