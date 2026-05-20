# ``History_Lib``

Collect, browse, search, summarize, deduplicate, and re-export browser history
records on Apple platforms.

## Overview

HistoryLib is a SwiftUI app backed by SwiftData. It imports browser history
records, stores them as persistent `Item` models, and presents the library by
year, month, and day. It can also generate summary snapshots, fetch and cache
site favicons, export records, and keep history data in sync through CloudKit.

The current import surface is focused on Safari history exports and the
HistoryLib native `.hlz` archive format. The native archive format is designed
for large history datasets by storing ordered JSONL chunks plus validation and
time-bucket indexes inside one ZIP container.

## Core Concepts

- `Item`: one imported browser history record.
- `SummarySnapshot`: persisted aggregate statistics for the library.
- Safari import: reads Safari history export JSON files, folders, or ZIPs.
- HistoryLib import: reads `.hlz`, ZIP, or folder archives with a
  `manifest.json`.
- HistoryLib export: writes one `.hlz` archive with chunks, indexes, and an
  optional summary snapshot.
- Cloud write protection: blocks history mutations when iCloud sync is enabled
  but the CloudKit-backed SwiftData store is unavailable.

## Data Flow

1. A user selects a file, folder, or archive from the Manage tab.
2. `HistoryImporter` resolves the input as Safari or HistoryLib format.
3. The format-specific importer validates and decodes records.
4. Records are deduplicated before insertion.
5. Records are saved as SwiftData `Item` models.
6. The UI refreshes summary statistics, directory skeletons, and search state.
7. A `SummarySnapshot` is generated and persisted.

Export follows the reverse direction: SwiftData records are enumerated in
visit-time order, encoded to the requested format, and packaged into a temporary
file that is handed to the system file exporter.

## Topics

### Project Documentation

- <doc:Project-Structure>
- <doc:HistoryLib-Archive-Format>
- <doc:Privacy-and-Data>
- <doc:Development>
