# Project Structure

This document describes how code is organized in `HistoryLib`.

## Goals

- Keep feature code discoverable.
- Separate UI, model, and service responsibilities.
- Make future platform-specific changes easier.

## Top-Level Layout

```text
HistoryLib/
├── App/                 # App entry and root composition
├── Features/
│   ├── Library/         # History browsing/search UI
│   ├── Summary/         # Summary models and views
│   └── Manage/          # Settings/manage actions UI
├── Models/              # Persistent data models
├── Services/
│   ├── Import/          # Import pipelines and parsers
│   ├── Export/          # Export pipelines and archive writers
│   ├── Favicon/         # Favicon fetch/cache logic
│   └── Sync/            # iCloud settings sync and duplicate cleanup
├── Shared/              # Shared view/action composition helpers
├── Assets.xcassets/     # App assets
├── Settings.bundle/     # iOS Settings app integration
├── Localizable.xcstrings
└── Info.plist
```

## Folder Rules

- `App/`: only app lifecycle and top-level navigation composition.
- `Features/*`: feature-owned SwiftUI views and small feature models.
- `Models/`: SwiftData entities and core domain model types.
- `Services/*`: side-effectful code (I/O, parsing, export, cache, networking).
- `Shared/`: reusable UI/action glue used by multiple features.

## Current Feature Areas

- `Features/Library/`: browsing, grouped directory display, search results,
  record rows, pagination, and record opening/deletion interactions.
- `Features/Summary/`: persisted summary snapshots and summary presentation.
- `Features/Manage/`: import, export, sync check, cache clearing, and optional
  batch deletion controls.

## Service Boundaries

- `Services/Import/`: resolves input format and imports Safari or HistoryLib
  archive sources. Shared deduplication and decoding helpers (URL
  normalization, dedup signatures, near-duplicate tolerance, flexible integer
  decoding, array chunking) live in one place here and are reused by every
  importer and by `Services/Sync/`; they are not duplicated per importer.
- `Services/Export/`: exports Safari-compatible ZIP files and HistoryLib
  `.hlz` archives.
- `Services/Favicon/`: fetches, validates, caches, and clears site icons.
- `Services/Sync/`: syncs settings through iCloud key-value storage and removes
  duplicate history records after CloudKit changes.

## Naming Conventions

- File names use `PascalCase` with `_` separators when needed.
- Avoid `+` in file names.
- Keep code identifiers, comments, and documentation in English.
- User-facing in-app strings are localized, not hard-coded English. They go
  through the String Catalog and must ship a translation for every supported
  language. See <doc:Localization>.

## Placement Guidelines

- New import logic goes under `Services/Import/`.
- New export formats or archive logic go under `Services/Export/`.
- New tabs/pages get their own folder in `Features/`.
- Cross-feature helpers go to `Shared/` only when reused.
- Deduplication and record-decoding helpers are shared, single-source
  utilities; reuse them instead of re-implementing per importer or cleaner.
