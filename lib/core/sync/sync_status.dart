/// The health of the most recent (or currently in-flight) sync attempt —
/// reported by `sync_trigger.dart`'s `onStatusChanged` callback after
/// every attempt. On its own this doesn't distinguish "guest mode,
/// nothing to sync" from "logged in but broken": `SyncEngine.syncAll`
/// fails every collection via `_requireOwner()` whenever there's no
/// session, so a UI combining this with account state should ignore it
/// entirely while logged out.
enum SyncStatus {
  /// A sync attempt is currently running.
  syncing,

  /// The most recent sync attempt completed with no failures.
  idle,

  /// The most recent sync attempt had at least one collection fail to
  /// push or pull (see `SyncOutcome.hadError`) — a network issue, a dead
  /// session, etc. Always best-effort and retried on the next trigger.
  error,
}
