# Privacy and Data

HistoryLib is built around browser history data. URLs, page titles, visit
timestamps, source browser names, and redirect metadata can reveal private
activity. Treat local databases, iCloud data, and exported files as sensitive.

## Data Stored by the App

History records are stored as SwiftData `Item` models. A record can contain:

- URL
- title
- visit timestamp
- visit count (when records are deduplicated, counts are merged/summed rather
  than discarded)
- source browser
- source file name
- original timestamp in microseconds
- optional source URL and timestamp
- optional destination URL and timestamp
- optional HTTP GET metadata
- import timestamp

Summary snapshots are stored as SwiftData `SummarySnapshot` models. They contain
aggregate counts and top-site statistics derived from the imported records.

## Local Storage

iCloud sync is opt-in and off by default. Out of the box, HistoryLib uses a
local SwiftData store, and browser history stays on the current device unless
the user exports it, includes it in a backup, or shares the app container
through system tools. Syncing history to iCloud only happens after the user
explicitly turns it on.

If local persistent storage cannot be initialized, the app can fall back to an
in-memory store to remain launchable. In-memory data is not durable.

## iCloud and CloudKit

When iCloud sync is enabled, HistoryLib tries to initialize SwiftData with
CloudKit. In this mode, imported history records can sync through the user's
iCloud account.

The storage backend is selected when the store is created at launch. Changing
the iCloud Sync setting takes effect on the next launch, and the app tells the
user a relaunch is needed. Until then, history mutations stay protected so the
on-disk data never diverges from the selected mode.

If CloudKit is unavailable while iCloud sync is enabled, HistoryLib blocks
history mutations such as import and delete. This prevents the app from creating
local-only changes that would diverge from the intended CloudKit-backed data
set.

User settings are synced separately through `NSUbiquitousKeyValueStore` when
iCloud sync is enabled.

## Favicon Fetching

When site icons are enabled, HistoryLib may request favicon resources for hosts
found in history records. The favicon service can:

- fetch HTML from a page URL or site root to discover icon links;
- request standard icon paths such as `/favicon.ico`,
  `/apple-touch-icon.png`, and `/apple-touch-icon-precomposed.png`;
- cache valid image data on disk and in memory;
- remember temporary misses to avoid repeated failed requests.

These network requests can disclose visited domains to the destination servers.
Disable site icons if that is not acceptable for your use case.

## Exported Files

HistoryLib can export records as Safari-compatible ZIP files and as HistoryLib
`.hlz` archives. These exports contain browser history records and should be
handled as private data.

Native `.hlz` archives are ZIP containers. They are not encrypted.

## Cache Clearing

The Clear Cache action removes cached favicon files and related in-memory icon
state. It does not delete history records, summary snapshots, exported files, or
iCloud data.

## Logging

The app prints persistence backend information during launch and may print
debug-only background deduplication errors. Avoid adding logs that include full
URLs, titles, or exported record payloads.
