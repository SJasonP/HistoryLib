# HistoryLib Archive Format

Status: v1 (current)

- File extension: `.hlz`
- Container: ZIP (single file shown to users)
- Primary goal: reliable import/export for very large history datasets

## 1. Overview

HistoryLib always exports one archive file (`.hlz`).
Inside the archive, data is split into ordered chunk files to keep import stable on large datasets.

## 2. Archive Layout

```text
archive.hlz
├── manifest.json
├── chunks/
│   ├── 00000001.jsonl
│   ├── 00000002.jsonl
│   └── ...
├── indexes/
│   ├── chunks.json
│   ├── years.json
│   ├── months.json
│   └── days.json
└── summary/
    └── snapshot.json   (optional)
```

Notes:
- `chunks/*` are written in ascending visit-time order.
- ZIP compression is applied by the container (`deflate`).
- Chunk files themselves are plain JSONL (not pre-compressed).

## 3. Manifest (`manifest.json`)

Required and read first.

```json
{
  "format": "historylib",
  "format_version": 1,
  "created_at_usec": 1770000000000000,
  "app_name": "HistoryLib",
  "app_version": "1.0",
  "record_schema": "hl_record_v1",
  "record_count": 4278,
  "chunk_count": 12,
  "time_range_usec": {
    "min": 1577836800000000,
    "max": 1770000000000000
  },
  "chunk_encoding": "jsonl",
  "chunk_target_records": 50000,
  "feature_flags": [
    "prebuilt_time_indexes_v1",
    "summary_snapshot_v1"
  ],
  "indexes": {
    "chunks": "indexes/chunks.json",
    "years": "indexes/years.json",
    "months": "indexes/months.json",
    "days": "indexes/days.json"
  },
  "summary": "summary/snapshot.json"
}
```

## 4. Chunk and Record Rules

Chunk file naming:
- `chunks/00000001.jsonl`
- `chunks/00000002.jsonl`

Rules:
1. Global order by `ts` ascending.
2. In-chunk order by `ts` ascending.
3. Default target size: `50,000` records per chunk.
4. Empty chunks are not allowed.
5. Every chunk must have an entry in `indexes/chunks.json`.
6. `sha256` in `indexes/chunks.json` is computed from the exact chunk file bytes.

Record schema (`hl_record_v1`) minimal required fields:
- `u` string: URL
- `ts` int64: visit timestamp (Unix microseconds, UTC)

## 5. Index Files

- `indexes/chunks.json`: chunk list + record count + time range + SHA256
- `indexes/years.json`: yearly counts/time range
- `indexes/months.json`: monthly counts/time range
- `indexes/days.json`: daily counts/time range

These indexes are for faster validation/import planning and future resume support.

## 6. Import Validation (v1)

Archive is valid only if:
1. `format == "historylib"`
2. `format_version` is supported
3. `record_count == sum(chunks.record_count)`
4. `chunk_count == chunks.json entry count`
5. chunk IDs are contiguous (`1..chunk_count`)
6. each chunk file exists and matches `sha256`
7. every chunk line decodes as a valid `hl_record_v1` record (`u` + `ts` required)
8. `record_count == 0` and `chunk_count == 0` is a valid empty archive

## 7. Compatibility

1. Unknown manifest fields must be ignored.
2. Unknown record fields must be ignored.
3. Missing required fields cause validation failure.
4. Future format changes must bump or extend `format_version`.

## 8. Privacy and Security

`.hlz` files are not encrypted. They are ordinary ZIP archives containing JSON
and JSONL files. Anyone who can open the archive can inspect the exported
history records.

The importer validates archive structure before trusting chunk files:

1. Archive-relative paths must stay inside the extracted archive root.
2. `manifest.json` must identify the format and supported version.
3. `indexes/chunks.json` must list contiguous chunk IDs.
4. Every listed chunk must exist.
5. Every listed chunk must match its SHA256 checksum.
6. Record counts in the manifest, chunk index, and chunk files must agree.

These checks protect against malformed archives and accidental corruption. They
do not provide confidentiality.
