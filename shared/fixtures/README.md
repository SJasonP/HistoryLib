# Shared Fixtures

This directory contains synthetic inputs for platform import,
export, deduplication, encryption, corruption, and compatibility tests.

Never place real browser history here. Every fixture must use fictional URLs,
titles, timestamps, and credentials and should document its expected result.

## Current fixture sets

- `import/safari-valid.json`: two valid Safari records, including numeric-string timestamps.
- `import/chrome-valid.json`: two valid Chrome Takeout records.
- `import/unknown-browser-history-string.json`: rejection case proving that a string value is not a Chrome format key.
- `dedup/cases.json`: canonical URL and signature cases shared by all clients.

All test clients must load these files directly rather than copying their contents into platform-local tests.
