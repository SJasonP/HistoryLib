# Development

This document captures the practical development workflow for HistoryLib.

## Opening the Project

Open `platforms/apple/HistoryLib.xcodeproj` from the repository root and use
the `HistoryLib` scheme.

The project currently contains three targets:

- `HistoryLib`
- `HistoryLibTests`
- `HistoryLibUITests`

The app target supports iOS and macOS. Test target platform settings may include
additional Apple platforms from Xcode's generated defaults, but the app code is
currently written for iOS and macOS.

## Command-Line Checks

Run the following commands from `platforms/apple`:

```sh
cd platforms/apple
```

List schemes:

```sh
xcodebuild -list -project HistoryLib.xcodeproj
```

Build:

```sh
xcodebuild -project HistoryLib.xcodeproj -scheme HistoryLib build
```

Run isolated hosted unit tests with a simulator available on your machine:

```sh
./scripts/test-unit.sh 'platform=iOS Simulator,name=iPhone 17'
```

The script configures an in-memory test host and runs `HistoryLibTests` without
opening personal history or starting normal cloud synchronization. UI regression
testing is described in <doc:Adaptive-Layout>. Build success and automated
tests do not replace interactive device acceptance.

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

- expose one smart-import entry point and detect Safari, Chrome, or HistoryLib
  content before inserting any records; reject the input when no format can be
  recognized instead of falling back to a user-selected format;
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

Safari import accepts JSON files, folders, and ZIP archives. Chrome import
accepts the same three layouts. HistoryLib import accepts `.hlz`, ZIP, and
folder archive layouts.

### Timestamps

`Item.rawTimeUsec` is always **microseconds since the Unix epoch**. The `.hlz`
exporter writes it back out verbatim, so a value on any other epoch silently
produces records centuries away and corrupts the archive's time-bucket indexes.
Any importer for a format that uses a different epoch must convert on the way
in. This is why Chrome support reads Google Takeout JSON — whose `time_usec` is
already Unix-based — rather than Chrome's local `History` database, which counts
from 1601.

### Chrome (Google Takeout)

Chrome has no built-in history export; Google Takeout is the only official
route. It produces `Takeout/Chrome/History.json` (older exports:
`BrowserHistory.json`), normally inside a ZIP, shaped as a single
`"Browser History"` array of per-visit records with `url`, `title`, and
`time_usec`. It carries no visit count, no redirect chain, and no metadata
block, so those fields are left at their defaults rather than invented.

Detection reads only the head of a file (looking for `"Browser History"` used as
a key) instead of decoding the document: Takeout history files are routinely
hundreds of megabytes, and a probe must never parse one just to return a Bool.
The check requires a following colon so that a record *titled* "Browser History"
is not mistaken for an export. Safari is probed before Chrome because both
browsers name their export `History.json`; only content tells them apart.

A Takeout folder holds unrelated JSON siblings (Autofill, SearchEngines, and so
on). Only files that pass the history sniff are imported; the rest are ignored
quietly rather than reported as failures.

The actual import also streams the JSON in 64 KiB blocks and decodes one visit
object at a time. It never retains the complete Takeout document or its full
record array in memory. Records are flushed through the shared deduplicator in
1,000-record batches, which keeps large imports viable on memory-constrained
iPhone and iPad devices.

## Export Rules

Exporters should:

- enumerate records in visit-time order;
- report progress for long-running exports;
- write to a temporary directory first;
- clean up temporary files after the system file exporter completes;
- preserve enough source metadata for round-trip import;
- keep the native `.hlz` format compatible with
  <doc:HistoryLib-Archive-Format>.
- never fall back to an unencrypted `.hlz` after password encryption fails;
- authenticate a password-protected archive completely before extracting or
  inserting any record, and enforce bounded KDF and frame parameters;
- keep passwords ephemeral and clean up temporary plaintext on success, error,
  and cancellation.

## Storage Recovery Protection

Mutation actions check `canMutateHistoryData` before writing history data.
An opened primary container accepts writes even when the network, cloud account,
quota, or transfers are unavailable. Sync diagnostics never control write access.
The `primary` backend marker means the normal container opened, not that remote
sync succeeded. If initialization fails, persistent and in-memory recovery modes
remain read-only for history, with a storage-error message.

Normal v1.4 operation follows system iCloud settings and retains the original
store location with automatic CloudKit integration. Build-compatibility recovery
is an explicit exception: stage a reset, restart before removing local files,
and open a separate local-only database with `.none`. Do not use cloud-backed
model deletions to reset a device. See <doc:Version-Compatibility>.

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
- encrypted archive round trips, wrong passwords, modified/truncated/reordered
  frames, missing final tags, trailing data, and malicious KDF parameters;
- checksum mismatch, manifest/chunk count mismatch, and malformed chunk lines;
- dedup merge behavior (visit counts are summed, not dropped);
- near-duplicate tolerance edge cases;
- storage recovery protection of import and delete, independent of sync errors;
- search pagination returning the expected matches without dropping results.

`HistoryLibUITests` should host real launch/flow assertions rather than template
stubs.

## Privacy Rules

History records are sensitive. New code should avoid logging full URLs, titles,
passwords, keys, or raw import/export payloads. Unencrypted `.hlz` files remain
plain ZIP containers; password protection is optional.

See <doc:Privacy-and-Data> before adding import, export, sync, cache, or logging
behavior.

## Localization Rules

HistoryLib supports all six product languages. Any user-facing
string you add must be localizable through the String Catalog and ship a
translation in all six product languages; do not display hard-coded English. See
<doc:Localization> for how strings are stored, the `String(localized:)` pattern
for code-built messages, and the separately localized Settings bundle.
