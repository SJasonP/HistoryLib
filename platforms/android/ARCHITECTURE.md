# Android Architecture

This is the implementation boundary for the Android 1.4 client. Product
behavior remains authoritative in `../../shared/specs`; this file defines where
Android code belongs.

## Modules

```text
:app ─────────────► :core
  └───────────────► :transfer ─────────► :core
```

- `:app` owns Compose UI, activities, Android document-picker adapters,
  persistence implementations, platform services, and the application
  composition root.
- `:core` owns platform-neutral history models plus repository, settings, and
  sync contracts. It must not import Android, Compose, or `:transfer` APIs.
- `:transfer` owns platform-neutral import/export requests, reports, progress,
  and stream abstractions. It may depend on `:core`; it must not expose Android
  `Uri`, `Context`, activities, Compose, or app feature types.

`./gradlew checkArchitecture` enforces the most important source boundaries and
is included in each module's `check` lifecycle.

## Dependency injection

`app/.../di/HistoryLibDependencies.kt` is the composition boundary. Concrete
Room, DataStore, transfer, favicon, storage, and sync-status implementations are
constructed in `:app` and exposed through contracts. Feature code depends on
those contracts rather than generated containers or concrete storage classes.

## UI structure

The app has three stable top-level destinations: Summary, Library, and Manage.
`NavigationSuiteScaffold` selects native bottom-bar or navigation-rail behavior
for the available window size. Summary observes persisted aggregate snapshots.
Library observes compact day counts, then loads records in 200-row pages only
for expanded days or debounced searches. Manage owns explicit import/export,
settings, cache inspection, and confirmed deletion workflows.

Do not introduce a route library just to switch these three destinations.
Navigation3 can be added when a feature gains an actual nested route stack.

## Data and transfer invariants

- Room owns history, import-run audit data, directory counts, and summary
  snapshots. Derived tables refresh once after a mutating import, not after each
  batch. Exported schemas under `app/schemas` are the migration baseline.
- Merge serializes mutations and chunks lookup queries below SQLite's bind
  limit. Cross-platform unique-key and time-tolerance rules live in `:core`.
- Import detection inspects structured content. Unknown input is rejected before
  mutation; ZIP entry names/counts/sizes, JSON object sizes/depth, HLZ hashes,
  and every JSONL record are validated with bounded streaming reads.
- Document-provider streams and temporary files are scoped to an operation.
  Password character arrays are cleared when a transfer completes or is
  cancelled.
- Favicon retrieval is optional, bounded, cancellable, and clearable. Sync uses
  an explicit unsupported service for Android 1.4 rather than pretending to be
  enabled.

Behavior remains authoritative in `../../shared/specs`; cross-platform changes
must add or update synthetic fixtures under `../../shared/fixtures` and retain
the strict no-write guarantee for unrecognized input.
