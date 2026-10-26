# Privacy and Data

The platform-neutral privacy contract is maintained at
[`shared/specs/privacy-and-data.md`](../../../shared/specs/privacy-and-data.md).
This topic documents the Apple implementation details that satisfy it.

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
in-memory store to remain launchable. In-memory data is not durable: history
mutations are blocked and a storage error is shown until a working persistent
store can be opened after relaunch.

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

## Library Directory Cache

The Library tab groups records by year, month, and day and shows a record count
for each group. Those counts are derived from a per-day count map, which is
cached on disk (`directory-count-cache.json` in Application Support) so the app
can display every count on launch without rescanning the whole store.

This cache is device-local by design and never syncs to iCloud: it is not part
of the SwiftData/CloudKit schema, day boundaries depend on the device's time
zone, and it is excluded from device backups. It is recomputed whenever history
records are imported or deleted, and it self-heals: on launch the cached total is
compared against the live store count (and the recorded time zone), and any
mismatch triggers a full rescan. Clearing the cache and rebuilding it never
changes any history record.

## Favicon Fetching

When site icons are enabled, HistoryLib may request favicon resources for hosts
found in history records. The favicon service can:

- fetch HTML only from the site origin to discover icon links, without the
  recorded page path, query, fragment, or credentials;
- request standard icon paths such as `/favicon.ico`,
  `/apple-touch-icon.png`, and `/apple-touch-icon-precomposed.png`;
- cache valid image data on disk and in memory;
- remember temporary misses to avoid repeated failed requests.

Icon discovery remains at the same origin, HTTPS is not downgraded to HTTP,
and redirects are not followed. These requests can disclose visited domains
and the client IP address to destination servers.
Disable site icons if that is not acceptable for your use case.

## Exported Files

HistoryLib can export records as Safari-compatible ZIP files and as HistoryLib
`.hlz` archives. These exports contain browser history records and should be
handled as private data.

Native `.hlz` archives are ZIP containers when no password is supplied. A
password-protected export wraps the ZIP in authenticated encryption using
Argon2id password-based key derivation and XChaCha20-Poly1305 secretstream.
Password-protected files can only be opened by a compatible HistoryLib version.

Passwords are held only for the current import or export operation and are not
stored by the app. Forgotten passwords cannot be recovered. Encryption cannot
compensate for an easily guessed password; the app warns about passwords shorter
than 12 characters.

The app must create temporary plaintext while packaging an export and after
decrypting an import for ZIP validation. These files remain in the app sandbox,
are excluded from backups, use complete file protection on iOS, and are removed
after success, failure, or cancellation.

## Cache Clearing

The Clear Cache action reports the clearable cache size separately from the
non-clearable history data, then removes the contents of the app's Caches and
temporary directories, related in-memory icon state, and the Library directory
count cache after user confirmation. In-flight favicon requests are cancelled so
they cannot repopulate the cache after clearing. It does not delete history
records, summary snapshots, exported files, or synced data. The directory count
cache is rebuilt when a later data refresh or app launch requires it.

The non-clearable data value is calculated as the app's sandbox data minus the
clearable cache. This is equivalent to total local storage minus the app bundle
and clearable cache, without unnecessarily scanning the app bundle. It includes
history records, settings, and other data that cannot be removed by Clear Cache.
Its size is determined mainly by the number of imported history records and
Apple's storage management. HistoryLib cannot control, reduce, or clear it.
System Settings may use different accounting rules, so its displayed value may
differ.

## Logging

The app prints persistence backend information during launch and may print
debug-only background deduplication errors. Avoid adding logs that include full
URLs, titles, or exported record payloads.
