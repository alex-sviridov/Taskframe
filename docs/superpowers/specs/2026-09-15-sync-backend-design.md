# Sync backend (multi-device sync via PocketBase)

## Purpose

Taskframe is currently local-only: every entity (tasks, categories,
templates, saved searches, day blocks) lives in an on-device `sembast`
database with no network layer. This adds a backend so the same person's
data can sync across their own devices (phone, web, etc.) — not
multi-user sharing, just one person's data following them around.

## Scope

In scope:
- A self-hosted PocketBase instance as a second Docker service
- No-login "pairing code" identity: one device generates a code, other
  devices join a sync group by entering it
- Per-entity-type collections with a flexible JSON payload, so evolving
  a Dart model never requires a server schema migration
- A `SyncService` that pushes local changes and pulls remote changes,
  resolving conflicts by last-write-wins (`updatedAt` comparison)
- `updatedAt` and a `deleted` tombstone added to every synced model
- Tests for the LWW merge logic and for push/pull against a local
  PocketBase instance

Out of scope:
- Real user accounts (email/password, third-party sign-in)
- Multi-user sharing/collaboration on the same data
- Field-level merge or manual conflict resolution UI
- Realtime push (PocketBase supports websocket subscriptions, but v1
  syncs on a timer/app-start/reconnect only — realtime is future work)
- Any change to sembast as the local source of truth or to how the app
  behaves offline

## Decisions

- **PocketBase, not a custom server, not CouchDB.** PocketBase is a
  single Go binary + embedded SQLite with an official Dart SDK, built-in
  auth, and auto `updated` timestamps per record — it gives LWW almost
  for free and needs no custom server code for v1, just collection
  config. CouchDB's native replication is attractive for sync in theory,
  but its MVCC conflict model keeps *both* conflicting revisions and
  expects app-level resolution, which fights the LWW choice below, and
  Dart/Flutter has no PouchDB-equivalent client — we'd hand-roll HTTP
  polling of the `_changes` feed for no real benefit over PocketBase.
- **SQLite, one container.** PocketBase embeds SQLite itself, so
  "single container" was already the natural shape — no separate DB
  service to run, back up, or administer. Deployed as a second service
  alongside the existing `Dockerfile`/`nginx.conf` setup, with its data
  directory on a volume.
- **No accounts — pairing code as the auth mechanism.** A `sync_groups`
  PocketBase auth collection where the pairing code doubles as the
  record's password. The first device creates the group (generates a
  random code, e.g. 6 alphanumeric characters) and authenticates
  immediately; other devices "join" by entering the code into
  PocketBase's normal password-auth endpoint. Every other collection's
  API rule scopes reads/writes to `sync_group = @request.auth.id`, so a
  device only ever sees its own group's records. This avoids building
  and maintaining any account system for what is explicitly a
  single-person, multi-device feature.
- **One collection per entity type, each with a flexible `data` JSON
  field.** Collections: `tasks`, `categories`, `templates`,
  `template_blocks`, `saved_searches`, `day_blocks`. `template_blocks`
  (the events inside a template, currently stored separately via
  `TemplateBlocksRepository`) is included alongside `templates` so a
  synced template actually carries its contents, not just its name.
  Each record has `id`, `sync_group`,
  `updated` (PocketBase-managed), `deleted` (bool tombstone), and `data`
  (JSON blob holding the entity's actual fields, mirroring the shape
  already produced by each feature's existing sembast serialization).
  This means adding a field to, say, `Task` never requires a PocketBase
  schema change — matches the "not too rigid" requirement directly.
- **`updatedAt` and `deleted` are added to every synced Dart model and
  its sembast storage**, not just the sync layer — LWW needs a
  comparable timestamp regardless of backend, and soft-delete tombstones
  are required so a delete on one device can propagate to another
  instead of being silently resurrected by an unrelated push. This is
  the one change to existing repositories; the repository interfaces
  otherwise stay as-is.
- **Sync is a separate `SyncService`, not folded into the repositories.**
  Repositories keep talking to sembast exactly as today. `SyncService`
  reads/writes through the existing repository interfaces and talks to
  PocketBase's Dart SDK independently, so the local-first behavior of
  the app (works fully offline, sync is best-effort) isn't entangled
  with normal read/write code paths.
- **Sync triggers: app start, connectivity regained, and a foreground
  timer (~30s).** No realtime subscriptions in v1 — simplest thing that
  keeps devices reasonably close to in-sync without adding websocket
  lifecycle management on top of everything else.
- **Conflict resolution is last-write-wins by `updatedAt`, full stop.**
  No field-level merging, no user-facing conflict UI. For a single
  person's own planner data, true simultaneous edits to the same record
  from two devices are rare, and the cost of building anything more is
  not justified.

## Data flow

1. **Local edit:** a repository write (e.g. `TaskRepository.update`) sets
   `updatedAt = now()` as it already persists to sembast — no behavior
   change from the user's perspective.
2. **Push:** `SyncService` queries each repository for records with
   `updatedAt` newer than that repository's last-synced cursor, and
   upserts them to the matching PocketBase collection (creating the
   `data` JSON payload from the existing model's serialization).
3. **Pull:** `SyncService` fetches records from each PocketBase
   collection with `updated` newer than the last pull cursor (scoped
   automatically to the device's `sync_group` by the API rule). For each
   returned record, compares `updated` to the local copy's `updatedAt`;
   if the remote is newer, applies it locally (including honoring
   `deleted` as a delete); otherwise ignores it.
4. **Cursors** (last-push and last-pull timestamps) are stored locally
   per entity type, e.g. via the existing `AppSettingsRepository`.

## Error handling

- No network / PocketBase unreachable: push/pull fail silently, retried
  on the next trigger (start/reconnect/timer). The app never blocks on
  sync — every screen reads/writes local sembast only.
- Partial failure (some records pushed, then a request fails): cursors
  only advance past records that were confirmed written, so a retry
  naturally resumes from where it left off without re-sending everything.
- Pairing code entered wrong / group not found: surfaced as a plain
  error in the pairing UI; no retry loop, no local data touched.

## Testing

- Unit tests for the LWW comparator (`SyncService`'s merge decision)
  covering: remote newer, local newer, equal timestamps, remote
  tombstone vs local edit, local tombstone vs remote edit.
- Unit tests for cursor advancement on partial-failure push/pull.
- Integration tests running push/pull against a local PocketBase
  instance (started the same way other local dev/test infra in this
  repo is scripted, e.g. via `make`/Docker), covering: fresh pair-and-
  sync, edit-on-device-A-appears-on-device-B, delete propagation,
  concurrent edit resolves to the newer `updatedAt`.
- No new UI beyond a pairing screen (enter/generate code), which gets
  the same widget-test treatment as other screens in this repo.
