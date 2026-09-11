# PWA support (local persistence + iOS install)

## Purpose

Taskframe currently keeps all data (day blocks, categories, templates) in
memory — a fresh page load wipes everything. This design makes Taskframe a
real installable PWA: data survives reloads via local (client-side)
storage, and iOS Safari users — who have no native "install" prompt — are
guided to add it to their home screen. A future stage will add backend
sync on top of the same repository interfaces; this design does not
implement sync.

## Scope

In scope:
- Persistent implementations of the three existing repository interfaces
  (`DayBlocksRepository`, `CategoryRepository`, `TemplateRepository`),
  backed by `sembast`/`sembast_web`, replacing the `InMemory*`
  implementations in the Riverpod providers on every platform (web,
  iOS, Android) with one shared code path
- First-run seeding of the current hardcoded seed data (today's sample
  blocks, the default category), so a fresh install behaves like today
- `web/index.html` and `web/manifest.json` updates for correct iOS PWA
  behavior: viewport meta tag, iOS-specific meta tags, theme-color, a
  180×180 apple-touch-icon
- An explicit `--pwa-strategy=offline-first` build flag, documented in the
  Makefile
- A dismissible in-app banner teaching iOS Safari users (not already
  running standalone) how to install via Share → Add to Home Screen
- A best-effort `navigator.storage.persist()` call on web startup
- Unit tests for the new repositories and the install-hint banner's
  show/hide/dismiss logic

Out of scope:
- Backend sync (the repository interfaces are written so a future
  `Api*Repository` can implement them unchanged, but no networking code
  is added here)
- Any change to the web rendering pipeline. Flutter web no longer ships an
  "html" DOM renderer (removed in Flutter 3.29); this project stays on
  CanvasKit
- A genuinely separate DOM-based web frontend
- Per-device iOS splash-image tags (iOS 15.4+ auto-generates a splash
  screen from the manifest icon + background color, which is sufficient)
- Migrating existing in-memory data on upgrade — there is no existing
  persisted data to migrate from

## Decisions

- **Storage: `sembast` + `sembast_web`.** A NoSQL document store with one
  API across native (file-backed) and web (IndexedDB-backed) platforms.
  Chosen over `hive_ce` for its built-in `Filter`/`Finder` query support,
  which fits the day-blocks "find all records for this date" access
  pattern without hand-rolled indexing. Chosen over raw
  `shared_preferences`/localStorage because iOS Safari's storage limits
  and eviction behavior are more forgiving for IndexedDB than for
  localStorage, and because the data (lists of blocks/categories/
  templates) is naturally record-shaped rather than a handful of flat
  key-value pairs.
- **Manual `toMap()`/`fromMap()` on the existing plain model classes**,
  matching the project's current style (no `freezed`/`json_serializable`
  anywhere in the codebase, no build_runner dependency). Adding code-gen
  tooling for three small models isn't warranted.
- **One database, three stores.** A single `Database` instance (opened
  once in `main()`, before `runApp`, exposed via a `sembastDatabaseProvider`)
  with separate stores named `day_blocks`, `categories`, `templates`.
  Simpler than three separate database files, and sembast stores are
  cheap and isolated enough that there's no benefit to splitting further.
- **Day blocks keyed by `id`, with a stored `dateKey` field** (a
  `yyyy-MM-dd` string). `load(date)` becomes
  `Finder(filter: Filter.equals('dateKey', ...))` instead of the current
  in-memory seed-and-suppress-by-id logic. The `_movedSeedIds` /
  `_seedFor` split in `InMemoryDayBlocksRepository` goes away entirely —
  seed data is written once at first run and from then on is
  indistinguishable from user-created data.
- **First-run seeding runs once, gated on an empty store**, not on every
  app start. On first launch (empty `day_blocks` store and empty
  `categories` store), write today's current hardcoded seed blocks and
  the default category, then never touch them again. This preserves the
  current "fresh install has sample data" behavior without needing an
  ongoing seed/suppress mechanism.
- **Persistence applies to every platform, not just web.** iOS/Android
  builds get real persistence as a side effect of switching off
  `InMemory*`, using the same `sembast` (native, file-backed) rather than
  `sembast_web`. One implementation, no platform-conditional repository
  code — `sembast`'s package already picks the right backend per
  platform via conditional imports.
- **iOS install hint is a dismissible banner, not a blocking modal.**
  Shown once per session inside `AppShell` when running as web, on an
  iOS user agent, and not already in standalone display mode
  (`window.matchMedia('(display-mode: standalone)')`). Dismissal is
  persisted (in the same sembast database, a small `settings` store) with
  a ~14-day cooldown before it reappears, so it doesn't nag on every
  visit but also doesn't disappear forever after one accidental dismiss.
- **`theme-color` meta tag is added independently of `manifest.json`**
  because iOS Safari's tab/status-bar chrome color reads the HTML meta
  tag, not the manifest's `theme_color` field, unlike Android Chrome.
- **`navigator.storage.persist()` is called but not relied upon.** Its
  real-world effect on iOS Safari is limited/inconsistent; it's a free
  best-effort call, not a durability guarantee. The actual reliability
  lever for iOS is getting the user to add the app to their home screen,
  which is what the install-hint banner is for.

## Data flow

1. `main()` opens the sembast database (via `databaseFactoryWeb` on web,
   `databaseFactoryIo` on native) before `runApp`, and runs the first-run
   seed check.
2. The `dayBlocksRepositoryProvider`, `categoryRepositoryProvider`, and
   `templateRepositoryProvider` (currently returning `InMemory*`
   instances) are changed to return `Sembast*Repository` instances backed
   by the opened database.
3. All existing call sites (screens, controllers) are unaffected — they
   depend only on the abstract repository interfaces, which don't change
   shape.
4. On web, the install-hint banner reads/writes its dismissal state
   through a small `settings` store in the same database.

## Error handling

- Database open failure (corrupt store, unsupported browser) is treated
  as fatal at startup — no fallback to in-memory, since silently losing
  persistence would be worse than a visible failure. This matches the
  project's current stance of not adding error handling for scenarios
  that can't realistically happen in supported browsers/OSes.
- Individual repository operations (`add`/`update`/`delete`) propagate
  `sembast` errors unchanged; nothing new needs to catch or wrap them, matching how the in-memory versions behave today.

## Testing

- Repository tests: same test-per-behavior coverage the current
  `InMemory*` repositories presumably have, run against `sembast`'s
  in-memory database factory (`databaseFactoryMemory`) — fast, no
  browser required, exercises real seeding/filtering/CRUD logic instead
  of mocks.
- Install-hint banner: a widget test covering shown-when-iOS-and-not-
  standalone, hidden-when-dismissed, and hidden-when-already-standalone.
- Not unit-testable, verified manually: actual iOS "Add to Home Screen"
  behavior, icon/splash rendering, and standalone launch — covered by
  manual verification on the existing e2e Playwright setup and/or a real
  device/simulator, not new automated tests.

## Future work

- Backend sync: a new `Api*Repository` implementing the same three
  interfaces, with the `sembast` repositories becoming an offline cache/
  outbox rather than the source of truth.
- Re-evaluating the Skwasm renderer for resource savings once it's more
  mature and iOS Safari's WASM-thread support is solid — deferred here
  since it's an unrelated, independently-decidable change.
