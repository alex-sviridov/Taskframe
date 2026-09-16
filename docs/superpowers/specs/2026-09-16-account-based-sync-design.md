# Account-based sync (replaces pairing-code identity)

## Purpose

The original sync design (`2026-09-15-sync-backend-design.md`) identified a
device's sync group by a shared pairing code, with no real user accounts.
This replaces that identity model with native PocketBase email/password
user accounts, while keeping the app fully usable, local-only, without an
account ("guest mode"). A guest who later registers or logs in gets their
local data merged into that account and starts syncing across devices.

This spec **supersedes** `2026-09-15-sync-backend-design.md`'s "No
accounts — pairing code as the auth mechanism" decision and everything
downstream of it (the `sync_groups` collection, `createGroup`/`joinGroup`,
the pairing screen). Everything else that spec decided — PocketBase as the
backend, per-entity-type collections with a flexible `data` JSON field,
`updatedAt`/`deleted` on every synced model, the generic `SyncEngine`'s
last-write-wins push/pull logic, sync triggers — is unchanged and this
spec builds directly on that existing implementation.

## Scope

In scope:
- A `users` PocketBase auth collection (email + password), replacing
  `sync_groups`
- Renaming the `sync_group` field to `owner` on all six data collections,
  and their API rules/unique index accordingly
- `PocketBaseSyncClient.register(email, password)` /
  `login(email, password)`, replacing `createGroup()`/`joinGroup(code)`
- Guest mode: no new mechanism — it's the existing "unauthenticated"
  behavior `SyncEngine`/`PocketBaseSyncClient` already have (sync
  throws/retries silently, app works entirely off local sembast)
- `logout()`: clears local synced data, sync cursors, and the stored
  session, returning the device to a clean guest state
- Reusing the existing sync-on-authenticate behavior (cursors at epoch)
  to merge a guest's local data into whatever account they register for
  or log into — no separate migration code
- An auth screen (email/password, register/login toggle, logout) replacing
  the pairing screen; the nav-shell entry relabeled "Account"

Out of scope:
- Email verification, password reset (PocketBase supports both; not
  built in this pass)
- Sharing one account's data with another account (still single-owner,
  same as the pairing design — just "owner" is now a real user, not a
  group)
- Any change to `SyncEngine`'s push/pull/LWW logic, the six collections'
  `data`/`updated_at`/`deleted` shape, or sync trigger cadence
- Rate limiting or other signup-abuse controls on registration: the
  `users` collection's `createRule: ''` means self-registration is fully
  open with no verification, so anyone who finds the PocketBase URL can
  create unlimited accounts. Not addressed in this pass — add before any
  non-personal deployment.

## Decisions

- **Real PocketBase `users` auth collection, identity = email.**
  Standard `passwordAuth.identityFields: ['email']`, `createRule: ''`
  (public — anyone can self-register, exactly PocketBase's normal
  sign-up posture), default password-length minimum restored (the
  6-character minimum in the pairing design existed only to match
  6-character pairing codes and no longer applies).
- **`sync_group` field renamed to `owner` across all six data
  collections**, same mechanics (a text field holding the authenticated
  record's id, `owner = @request.auth.id` on all four API rules, unique
  index `(owner, entity_id)`). This is a rename for clarity, not a new
  mechanism — a "user" is simply what "sync group" always meant, now that
  groups are real accounts instead of pairing codes.
- **No new guest-mode or migration mechanism.** `SyncEngine.syncAll`
  already treats "not authenticated" as a retryable failure (see the
  2026-09-15 spec's hardening: `PocketBaseSyncClient.upsert`/
  `listChangedSince` throw when unauthenticated rather than silently
  succeeding), so an unauthenticated device already behaves exactly like
  "guest mode" today — sync silently no-ops, the app works entirely off
  sembast. And because a freshly-authenticated device's push/pull cursors
  start at epoch, the very next sync after register/login naturally
  pushes every local guest record (all "newer than epoch") and pulls
  whatever the account already has — this is what satisfies "guest data
  merges into whichever account you log into," with no separate
  migration step to build or test.
- **Logout wipes local synced data**, chosen over "keep local data,
  just stop syncing," because leaving a stale copy of another session's
  private data on a shared/borrowed device is the wrong default for
  real accounts (unlike the old pairing design, where every device in a
  group was implicitly the same person). `logout()`:
  1. Clears all six synced sembast stores (`tasksStore`, `categoriesStore`,
     `templatesStore`, `templateBlocksStore`, `savedSearchesStore`,
     `dayBlocksStore`) completely — a hard clear, not a soft-delete/
     tombstone, since this is a local reset with nothing to propagate.
  2. Clears every `sync_push_*`/`sync_pull_*` cursor.
  3. Clears the stored auth token/identity — `AppSettingsRepository`'s
     `sync_group_token`/`sync_group_identity` keys are renamed to
     `account_token`/`account_identity` (no longer a "sync group"), and
     only these two keys are cleared — unrelated settings like the
     install-hint dismissal flag are untouched.
  4. Does **not** touch the PocketBase account or its server-side data —
     logging back in resumes normal sync and pulls it all back down.
  5. Does **not** re-run first-run seeding — the seed-completed flag in
     `AppSettingsRepository`/`settingsStore` is untouched, so the old
     hardcoded sample blocks don't reappear after a logout.
- **Auth screen replaces the pairing screen.** Same file (renamed/
  repurposed, not a new feature slotted in beside it): email + password
  fields, a Register/Login mode toggle, and — when a session exists —
  the logged-in email plus a "Log out" action. Errors (taken email, wrong
  password) surface as plain text in the screen, same pattern as the
  pairing screen's error handling today. The nav-shell entry point
  (added in the prior fix wave) is relabeled from "Sync devices" to
  "Account."

## Data flow

Unchanged from the 2026-09-15 spec's push/pull/LWW logic. What's new:

1. **Register:** `PocketBaseSyncClient.register(email, password)` creates
   a `users` record, authenticates, persists the session — exactly
   mirroring today's `createGroup()`.
2. **Login:** `PocketBaseSyncClient.login(email, password)` authenticates
   against an existing `users` record — exactly mirroring today's
   `joinGroup(code)`.
3. **First sync after register/login:** no special-cased migration logic.
   `SyncEngine.syncAll` runs on its normal triggers; because this
   device's cursors are at epoch, `_push` sends every local record and
   `_pull` fetches everything already on the account. LWW resolves any
   id collisions between guest-created and already-synced data the same
   way it resolves any other conflict — by `updatedAt`.
4. **Logout:** `logout()` runs synchronously before the auth screen
   reports "logged out" — clears the stores/cursors/session described
   above, then the UI reflects guest mode again.

## Error handling

- Registration with an already-used email, or login with wrong
  credentials: PocketBase's error surfaces as plain text in the auth
  screen, no retry loop, no local data touched — same posture as the
  pairing screen's existing error handling.
- Network/PocketBase unreachable during register/login: same error
  surface; the device stays in guest mode until the user retries.
- Everything else (offline sync behavior, partial-failure cursor
  advancement, retry cadence) is unchanged from the 2026-09-15 spec.

## Testing

- Unit tests for `PocketBaseSyncClient.register`/`login` mirroring the
  existing pairing-code tests' shape (moved from
  `pocketbase_sync_client_test.dart`'s pairing-code coverage).
- A `logout()` unit test verifying all six stores end up empty, all
  cursor keys are cleared, and the auth/session keys are cleared, while
  an unrelated settings key (e.g. the install-hint flag) survives.
- Integration tests (extending `test/integration/pocketbase_sync_test.dart`,
  which already runs against a live local PocketBase) covering: register
  → guest data appears on the account; login to an existing account with
  local guest data present → both merge; logout → local stores are empty
  and a subsequent login re-pulls everything.
- The existing three cross-device integration scenarios (edit
  propagation, delete propagation, concurrent-edit LWW) are retargeted to
  use `register`/`login` instead of `createGroup`/`joinGroup`, but are
  otherwise unchanged — this is a controlled regression check that
  swapping identity mechanisms didn't disturb sync correctness.
