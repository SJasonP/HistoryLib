# Changelog

All notable changes to HistoryLib are documented here. This project adheres to
[Keep a Changelog](https://keepachangelog.com/) and uses [Semantic Versioning](https://semver.org/).

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
