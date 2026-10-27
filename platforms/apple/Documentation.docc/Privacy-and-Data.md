# Privacy and Data

The platform-neutral privacy contract is maintained at
[`shared/specs/privacy-and-data.md`](../../../shared/specs/privacy-and-data.md).
This topic documents the Apple implementation details that satisfy it.

HistoryLib is built around browser history data. URLs, page titles, visit
timestamps, source browser names, and redirect metadata can reveal private
activity. Treat local databases, iCloud data, and exported files as sensitive.

## Application privacy lock

iOS and iPadOS use Apple's system Lock App feature. macOS uses HistoryLib's
default-on app privacy lock with LocalAuthentication; it can be disabled from
the app's Settings. The macOS lock uses Touch ID, Apple Watch, or the Mac
login password when available. HistoryLib never stores biometric data or
credentials. Authentication is required before the first usable library
content appears after launch, and a failed or cancelled request leaves the
library unavailable.

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

From v1.4, system iCloud settings control synchronization. HistoryLib's own
iCloud switch is removed, and its previously saved value is discarded. If
system settings permit access, records may sync even when the former in-app
switch was off. The release notes describe this behavior change. A local copy
remains in SwiftData. System backups and explicit exports are separate from sync.

If local persistent storage cannot be initialized, the app can fall back to an
in-memory store to remain launchable. In-memory data is not durable: history
mutations are blocked and a storage error is shown until a working persistent
store can be opened after relaunch.

## iCloud and CloudKit

HistoryLib initializes SwiftData with automatic CloudKit integration. The system
controls whether and when records sync; the app no longer maintains a second
sync preference or app-toggle relaunch requirement. The existing store location
and data model are retained. Recovery configurations explicitly use `.none`.

If the CloudKit-backed container cannot initialize and a recovery store is used,
HistoryLib blocks history mutations instead of silently writing to that fallback.
Temporary network loss alone does not block local changes in a working
CloudKit-backed store; the system manages pending synchronization.

User settings use `NSUbiquitousKeyValueStore` under the same system control.
Manage reads cloud history counts using paginated zone changes, requesting no
record fields/assets. Only history record identities and change tokens are held
in memory for the current visible session. No cloud count is inferred from the
local count, and failures do not appear as zero. Account availability does not
prove that the system's per-app iCloud switch is enabled.

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

Manage displays clearable cache, protected data, database size, and database
journal size. Measurements refresh only while Manage is visible and active.

Clear Cache removes Caches, known completed import/export/staging temporary
folders, icon state, the directory-count cache, and loaded search/day results.
It disables site icons and cancels their requests before clearing. Active
transfers disable the action. Unknown framework temporary files are retained.

SQLite is asked to checkpoint and truncate completed WAL pages without waiting
on active transactions. Busy journals are retained. The action does not unlink
history databases or their journals, delete indexes or sync metadata, execute
VACUUM, or remove history records. Reclaimable journal space may shrink; database
files and system-reported app usage are not guaranteed to shrink.

Protected data is sandbox data minus identified disposable caches. System
Settings may use different storage-accounting rules.

## Logging

The app prints persistence backend information during launch and may print
debug-only background deduplication errors. Avoid adding logs that include full
URLs, titles, or exported record payloads.
