# Privacy and Data Contract

Browser history is sensitive personal data. URLs, titles, timestamps, browser
names, redirect metadata, derived site rankings, and exported archives can
reveal private activity.

## Data boundary

- History remains in platform-private storage unless the user explicitly
  exports it or enables a documented sync feature.
- HistoryLib does not expose a product-level backup feature.
- Export is explicit data portability, not automatic backup.
- Sync is a separate feature and must not be described as backup.
- Real browser history must never be committed as a repository fixture.

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

## Logging

Production logs must not include full URLs, titles, passwords, archive record
payloads, decrypted content, or cloud credentials. Diagnostic events should use
counts, phases, error categories, and non-sensitive identifiers.

## Optional intelligent search

Apple's explicit on-device interpretation processes only the user's request and
reference date/time zone. It does not receive stored history or use a cloud
fallback. Proposed filters require user review before execution. Siri and
Shortcuts receive the query the user supplies, but the current app actions
return no history contents and create no system history index. See `search.md`.
