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

`SummarySnapshot` is derived data. If history records change, refresh summary
statistics and regenerate the latest snapshot.

## Import Rules

Importers should:

- validate input format before inserting records;
- skip incomplete records when the external format allows partial data;
- fail clearly when the archive format itself is invalid;
- batch inserts for large datasets;
- deduplicate before insertion;
- preserve source metadata when available.

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

## Privacy Rules

History records are sensitive. New code should avoid logging full URLs, titles,
or raw import/export payloads. Export files are private data and the native
`.hlz` format is not encrypted.

See <doc:Privacy-and-Data> before adding import, export, sync, cache, or logging
behavior.
