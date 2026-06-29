# Development

This document captures the practical development workflow for HistoryLib.

## Opening the Project

Open `HistoryLib.xcodeproj` and use the `HistoryLib` scheme.

The project currently contains three targets:

- `HistoryLib`
- `HistoryLibTests`
- `HistoryLibUITests`

The app target supports iOS and macOS. Test target platform settings may include
additional Apple platforms from Xcode's generated defaults, but the app code is
currently written for iOS and macOS.

## Command-Line Checks

List schemes:

```sh
xcodebuild -list -project HistoryLib.xcodeproj
```

Build:

```sh
xcodebuild -project HistoryLib.xcodeproj -scheme HistoryLib build
```

Run tests with a local simulator destination that exists on your machine:

```sh
xcodebuild \
  -project HistoryLib.xcodeproj \
  -scheme HistoryLib \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

## Code Organization

Use the project folder boundaries as ownership boundaries:

- `App/`: app lifecycle and root navigation.
- `Features/`: feature-owned SwiftUI views and small feature models.
- `Models/`: SwiftData persistent models and core data types.
- `Services/`: I/O, parsing, archive writing, caching, networking, sync, and
  other side-effectful work.
- `Shared/`: reusable view/action composition used by multiple features.

See <doc:Project-Structure> for the full layout.

## Data Model Rules

`Item` is the canonical persistent record for one history entry. Importers
should normalize and validate external payloads before creating `Item` values.

`Item` must declare SwiftData indexes for the fields the app sorts and filters
on. At minimum `visitedAt` (used by nearly every browse, export, summary, and
dedup query) and `uniqueKey` (used by dedup lookups) are indexed, so large
datasets do not fall back to full-table scans.

`SummarySnapshot` is derived data. If history records change, refresh summary
statistics and regenerate the latest snapshot.

## Import Rules

Importers should:

- validate input format before inserting records;
- skip incomplete records when the external format allows partial data;
- fail clearly when the archive format itself is invalid;
- batch inserts for large datasets;
- validate the whole archive (checksums, counts) before importing any record,
  so a corrupt archive imports nothing; then decode each chunk record exactly
  once (no double-decode) and never materialize a whole chunk as a single
  in-memory string;
- deduplicate before insertion;
- preserve source metadata when available.

When two records are treated as duplicates, deduplication merges them rather
than discarding data: visit counts are summed and the richer metadata is kept.
This applies to both import-time dedup and the background duplicate cleaner.

Deduplication helpers — URL normalization, dedup signatures, near-duplicate
tolerance, flexible integer decoding, and array chunking — are shared utilities
used by every importer and the duplicate cleaner. Do not copy these into
individual importers. The near-duplicate tolerance defaults to 1 second and is
defined in one place (`ImportDedupOptions`).

Safari import accepts JSON files, folders, and ZIP archives. HistoryLib import
accepts `.hlz`, ZIP, and folder archive layouts.

## Export Rules

Exporters should:

- enumerate records in visit-time order;
- report progress for long-running exports;
- write to a temporary directory first;
- clean up temporary files after the system file exporter completes;
- preserve enough source metadata for round-trip import;
- keep the native `.hlz` format compatible with
  <doc:HistoryLib-Archive-Format>.

## CloudKit Write Protection

When iCloud sync is enabled, mutation actions should check
`canMutateHistoryData` before writing history data. If the active backend is not
CloudKit, show a clear blocked-mutation message instead of silently writing to a
fallback local store.

This rule is important because history data is expected to be one synced data
set when iCloud sync is enabled.

The persistence backend (local vs. CloudKit) is chosen once when the store is
created at launch, from the saved iCloud Sync setting. Changing the iCloud Sync
setting therefore takes effect on the next launch. The app must:

- tell the user a relaunch is required after the setting changes; and
- keep write protection consistent with the **on-disk** backend until relaunch,
  so the active store never receives writes that contradict the selected mode
  (for example, never write to a CloudKit-backed store after the user has just
  turned iCloud sync off).

## Performance and Data Loading

The app targets very large history datasets, so data access should stay
predictable as the row count grows:

- Run history scans (search, directory build, export, summary, dedup) off the
  main thread, or in cancellable chunks that yield, so the UI never blocks on a
  store fetch.
- Walking the full table uses paged fetches that yield between pages and honor
  cancellation. Keyset/seek pagination is preferred, but it requires a unique,
  predicate-comparable cursor; `visitedAt` alone is not unique and Core Data
  does not guarantee a stable order among equal sort keys, so plain
  `fetchOffset` paging is retained until a unique ordering column exists. Do not
  replace it with a `visitedAt`-only cursor, which can drop or duplicate records
  that share a timestamp.
- Search must not silently cap how many records it considers; a query should not
  drop matches just because they fall past a per-page scan window.
- Do not run store queries from inside a SwiftUI `body` or from derived view
  state that recomputes on every render. Compute counts asynchronously and cache
  the result (for example, the batch-delete match count).
- Coalesce the post-mutation refresh work (summary stats, directory skeleton,
  search reset, snapshot regeneration) behind one debounced entry point so a
  burst of imports or deletes does not start several overlapping full-table
  scans.

## Testing

Tests should cover the data-integrity and safety paths, not only happy-path
round trips. Required coverage includes:

- archive path-traversal (zip-slip) rejection and symlink rejection;
- checksum mismatch, manifest/chunk count mismatch, and malformed chunk lines;
- dedup merge behavior (visit counts are summed, not dropped);
- near-duplicate tolerance edge cases;
- CloudKit write-protection gating of import and delete;
- search pagination returning the expected matches without dropping results.

`HistoryLibUITests` should host real launch/flow assertions rather than template
stubs.

## Privacy Rules

History records are sensitive. New code should avoid logging full URLs, titles,
or raw import/export payloads. Export files are private data and the native
`.hlz` format is not encrypted.

See <doc:Privacy-and-Data> before adding import, export, sync, cache, or logging
behavior.

## Localization Rules

HistoryLib fully supports English (US) and Simplified Chinese. Any user-facing
string you add must be localizable through the String Catalog and ship a
translation in both languages; do not display hard-coded English. See
<doc:Localization> for how strings are stored, the `String(localized:)` pattern
for code-built messages, and the separately localized Settings bundle.
