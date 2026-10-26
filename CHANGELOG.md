# Changelog

All notable changes to HistoryLib are documented here. This project adheres to
[Keep a Changelog](https://keepachangelog.com/) and uses [Semantic Versioning](https://semver.org/).

## [1.4] - Unreleased

This release ships only for Apple platforms (iOS and macOS). Android and
Windows releases are deferred; their source is not a shipping claim.

### Added

- Editable search filters for literal terms, domain, browser, and local dates.
- Optional on-device natural-language interpretation with manual fallback.
- Authenticated foreground Siri/Shortcuts search actions and the 27 system
  application-search schema. Results remain in HistoryLib; no history index or
  record content is donated to Siri by this implementation.
- Full resources for the six United Nations official languages.
- Apple privacy manifest and isolated, synthetic-data automated test tooling.

### Changed

- Adaptable tab/sidebar navigation, compact/regular library layouts, retained
  navigation routes, and fold-aware scrollable transfer progress for iPhone Duo.
- Repository structure separates native clients from shared specifications and
  synthetic fixtures. Apple archive/model compatibility remains unchanged.

### Fixed

- Prevent history mutations when persistent storage fails and only an in-memory
  recovery store is available.
- Cancel old search pages and clear their cursors when search conditions change.
- Complete translations for ZIP import entry-count and size-limit errors.
- Limit favicon discovery to the site origin, removing recorded URL paths,
  queries, fragments, and credentials from discovery requests.

## [1.3] - 2026-08-13

### Added

- Smart import for Chrome history exported through Google Takeout as a JSON
  file, folder, or ZIP archive.
- A Help page that explains HistoryLib's import options and introduces
  HistoryLib Helper for importing history from computers and additional
  browsers.

### Changed

- Large Google Takeout exports are now parsed as a stream and saved in batches
  to keep memory use bounded during import.
- Import guidance now includes Google Takeout alongside Safari exports and
  HistoryLib `.hlz` archives.

### Security

- Strengthened temporary-file protection for browser history extracted from
  Safari and Google Takeout ZIP archives.

## [1.2] - 2026-07-15

### Added

- Optional password protection for HistoryLib `.hlz` exports. Protected
  archives use Argon2id password-based key derivation and authenticated
  XChaCha20-Poly1305 streaming encryption; passwords remain hidden and are
  never stored by the app.
- Record counts for every year, month, and day in the Library, backed by a
  device-local count cache so large libraries can restore their directory
  structure without a full scan on every launch.
- Clear Cache now reports clearable cache and non-clearable data separately
  before asking for confirmation.

### Changed

- Import is now a single smart action that recognizes supported Safari exports
  and HistoryLib archives automatically, and rejects files whose format cannot
  be identified.
- Clear Cache now removes the app's cache and temporary files as well as the
  Library count cache, cancels in-progress site-icon downloads, and clearly
  explains what cannot be removed.
- The iCloud sync information dialog now explains that sync scheduling, status,
  and record-level control are managed entirely by Apple.
- Collapsing a year or month now releases its loaded record rows and
  cancels stale page loads, reducing memory use in very large libraries.

### Fixed

- Fixed a serious crash that could occur when expanding or collapsing a
  year or month containing a large number of history records.
- Fixed missing year and month record counts.
- Fixed ZIP export path handling across `/var` and `/private/var`, which could
  cause Safari or HistoryLib archive creation to fail on macOS.
- Strengthened temporary-file cleanup and protection for imports, exports, and
  password-protected archives.

## [1.1] - 2026-06-29

### Added

- Import now shows a progress bar with a Cancel button, like export, so large
  imports no longer look frozen. `.hlz` imports report determinate progress;
  Safari imports report per-file progress.
- Full localization for **English (US)** and **Simplified Chinese**, covering
  in-app strings, dynamic status/alert messages, enum labels, and the iOS
  Settings bundle. The App Store now lists both languages
  (`CFBundleLocalizations`).
- New app icon with light, dark, and tinted appearances (Icon Composer `.icon`).
- SwiftData indexes on `Item.visitedAt` and `Item.uniqueKey` for much faster
  browsing, search, export, and deduplication on large libraries.

### Changed

- Changing the iCloud Sync setting now applies on the next launch, and the app
  tells you a relaunch is required; history changes stay protected until then so
  on-device data cannot diverge from the selected mode.
- Deduplication now **merges** duplicate visits (visit counts are summed) instead
  of discarding them — both at import time and in the background cleaner.
- `.hlz` exports record the app's real version (read from the bundle).

### Fixed

- **Importing `.hlz` / `.zip` archives failed on iOS** with "ZIP entry path is
  outside destination directory." The archive safety check now validates each
  entry's relative path instead of comparing absolute paths, which broke on iOS
  because the temporary directory resolves through a `/var` → `/private/var`
  symlink. (Did not reproduce on macOS.)
- `.hlz` import now validates the whole archive (checksums and record counts)
  before importing anything, so a corrupt archive imports nothing; each record is
  decoded only once instead of twice.
- Search no longer silently skips matches that fall past a per-page scan window,
  and no longer blocks the UI while scanning.
- The batch-delete screen no longer runs a database count query on every redraw.
- Restored the `remote-notification` background mode required for CloudKit sync.

## [1.0]

- Initial release: import Safari history exports and HistoryLib `.hlz` archives;
  browse by year/month/day; search; summary snapshots; export to Safari ZIP and
  `.hlz`; deduplicate; optional iCloud sync.
