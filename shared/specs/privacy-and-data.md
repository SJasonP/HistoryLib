# Privacy and Data Contract

Browser history is sensitive personal data. URLs, titles, timestamps, browser
names, redirect metadata, derived site rankings, and exported archives can
reveal private activity.

## Data boundary

- History remains in platform-private storage unless exported or synced through
  a documented platform service. From Apple 1.4, system iCloud settings control
  synchronization; the removed app-level switch is no longer an opt-out.
  Explicit build-compatibility recovery is an exception: after confirmation
  and restart, a separate local-only library disables history/settings sync and
  cloud diagnostics. Its reset never submits cloud record deletions.
- HistoryLib does not expose a product-level backup feature.
- Export is explicit data portability, not automatic backup.
- Sync is a separate feature and must not be described as backup.
- Real browser history must never be committed as a repository fixture.

## Application privacy lock

HistoryLib protects the history library before showing usable app content:

- iOS and iPadOS rely on the system's Lock App feature. HistoryLib does not
  duplicate that device-level lock.
- macOS and Windows provide an app-owned privacy lock that is enabled by
  default and may be disabled in the app's Settings. The platform's native
  local authentication mechanism is used; HistoryLib never stores biometric
  templates, PINs, passcodes, or passwords.
- Android may rely on the device or manufacturer privacy container when one is
  available. A platform must not claim that every Android device provides a
  universal per-app lock unless it implements an app-owned fallback.

On platforms with an app-owned lock, authentication is required before the
first usable app content is shown after launch. A failed or cancelled
authentication leaves the library unavailable. The lock setting and
authentication state are device-local and never sync through iCloud or other
HistoryLib data channels. Authentication must cover every in-app entry point
that can reveal history, including imports, exports, shortcuts, and deep links.

## Stored record data

Platforms preserve the shared record fields:

- URL and title;
- visit timestamp and original microsecond timestamp;
- visit count;
- source browser and source file name;
- optional redirect source/destination URLs and timestamps;
- optional latest-visit HTTP GET flag;
- import timestamp;
- canonical deduplication key.

Summary snapshots and directory-count caches are derived data. Clearing or
rebuilding them must never mutate history records.

## Favicon disclosure

Fetching a favicon can disclose a visited domain to its server. The setting
must explain this effect, and disabling icons must stop new favicon requests.
Apple icon lookup uses only the origin and icon paths, not the original page
path/query/credentials. HTTPS is not downgraded; redirects are not followed.
Positive results and temporary misses may be cached to reduce repeated network
disclosure.

## Export and encryption

- Unencrypted `.hlz` files are ordinary ZIP containers with readable JSONL.
- Password-protected `.hlz` archives provide authenticated encryption according
  to `hlz-v1.md`.
- Passwords are held only for the active operation, are never stored, and
  cannot be recovered.
- A password shorter than 12 characters triggers a warning but can be accepted
  after explicit confirmation.
- Authentication failures do not distinguish wrong passwords from damaged or
  tampered ciphertext.

## Temporary data

- Plaintext temporary data stays in application-private storage.
- It is removed after success, failure, and cancellation.
- Platform backup or extraction configuration must not include decrypted
  temporary files or caches.
- Cache clearing cancels in-flight writers before removing cached data.
- Apple cache clearing may request a SQLite-managed WAL checkpoint/truncation.
  It never unlinks database/journal files, removes database indexes, or changes
  history/sync metadata. Busy journals are retained without waiting on readers.

## Logging

Production logs must not include full URLs, titles, passwords, archive record
payloads, decrypted content, or cloud credentials. Diagnostic events should use
counts, phases, error categories, and non-sensitive identifiers.

## Optional intelligent search (currently disabled on Apple)

The current Apple release does not run Apple Intelligence or expose the related
Siri and Shortcuts search actions. Manual keyword search and user-edited
structured filters remain available. If the optional Apple capability returns,
its on-device interpretation must process only the user's request and reference
date/time zone, must not receive stored history, and must not use a cloud
fallback. Proposed filters would require user review before execution. See
`search.md`.
