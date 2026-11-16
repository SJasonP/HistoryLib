# Browser History Import and Export Formats

Status: current cross-platform behavior

This document covers supported external browser JSON shapes. HistoryLib's own
archive format is specified separately in `hlz-v1.md`.

## Safari history JSON

A Safari history export is recognized only when its decoded metadata contains:

```json
{
  "metadata": {
    "browser_name": "Safari",
    "data_type": "history"
  },
  "history": []
}
```

`browser_name` and `data_type` comparisons are case-insensitive. Metadata can
also include `browser_version`, `export_time_usec`, and `schema_version`.

History entries support:

- `url`;
- `time_usec`;
- `visit_count`;
- `title`;
- `source_url` and `source_time_usec`;
- `destination_url` and `destination_time_usec`;
- `latest_visit_was_http_get`.

`url` and `time_usec` are required for a usable record. Integer fields accept a
JSON number or numeric string. Invalid records are skipped and included in the
reported skipped count. `visit_count` defaults to 1 and is clamped to at least
1.

Safari-compatible export writes the same envelope and supports one JSON file or
files split by year, month, or day, then packages the payload as a ZIP archive.
Records are emitted in visit-time order and preserve supported redirect
metadata.

Apple v1.4 also exports a standalone Google Takeout-compatible JSON document
with a top-level `Browser History` array. Each record contains `url`, `title`,
and `time_usec`. This is a portable Takeout-shaped export; it is not a Chrome
database restore format.

## Google Takeout Chrome history JSON

Supported Chrome history comes from Google Takeout and contains a top-level
`"Browser History"` array:

```json
{
  "Browser History": [
    {
      "url": "https://example.test/",
      "title": "Example",
      "time_usec": 1710000000000000
    }
  ]
}
```

- `url` and `time_usec` are required for a usable record.
- `title` is optional.
- `time_usec` accepts a JSON number or numeric string and uses Unix
  microseconds.
- Takeout does not supply visit count or redirect metadata; visit count defaults
  to 1 and optional metadata remains absent.
- The array is parsed as a stream; implementations must not decode a large
  Takeout document into one in-memory array.
- Malformed individual records contribute to the skipped count when the
  surrounding stream remains usable.

Chrome detection looks for `"Browser History"` as a JSON key, not merely as a
string value. Implementations may inspect a bounded prefix for detection but
must parse the full array for import.

Chrome's local SQLite `History` database and its 1601-based WebKit timestamps
are not supported by this contract.

## Directories and ZIPs

- Directory traversal recursively considers non-hidden JSON files.
- Chrome Takeout directories can include unrelated JSON siblings; only files
  identified as Chrome history are imported.
- ZIP containers follow the same detection after safe bounded inspection or
  extraction.
- ZIP extraction and temporary-file rules are defined by `smart-import.md` and
  `privacy-and-data.md`.
