# Product Parity Contract

Status: draft for HistoryLib 1.4

The Android implementation baseline is documented in
`platforms/android/docs/Android-1.4-Specification.zh-CN.md`.

## Release rule

HistoryLib 1.4 is ready only when the Apple, Android, and Windows clients pass
the same required behavior and interoperability checks. Platform-specific
internal build numbers may differ; the public product version must be 1.4.

## Required feature areas

- One content-detected Import action for Safari, Chrome Takeout, and HistoryLib
  archives. Unknown input is rejected rather than guessed.
- Import from supported files, folders, and ZIP containers.
- Browse records by year, month, and day.
- Search URL and title text.
- Open records in the platform's default browser.
- Fetch, cache, display, and clear site icons with equivalent privacy controls.
- Generate equivalent summary snapshots.
- Export Safari-compatible ZIP files and HistoryLib `.hlz` archives.
- Import and export password-protected `.hlz` archives.
- Apply the same URL normalization, deduplication tolerance, metadata merge,
  and visit-count rules.
- Provide equivalent deletion controls and destructive confirmations.
- Provide equivalent settings and sync state, subject only to documented
  platform limitations.
- Ship English and Simplified Chinese localization.

Sync follows `sync.md`: HistoryLib 1.4 uses platform-local sync, and a
platform may document that it ships without sync when platform-local sync is
technically impractical. Such a platform must expose an explicit unsupported
state and must not claim parity for sync.

Documented 1.4 limitation: Android ships without sync and exposes an explicit
unsupported state (see `platforms/android/docs/Android-1.4-Specification.zh-CN.md`).

## Allowed platform differences

- Visual design language, navigation components, menus, dialogs, and adaptive
  layouts may follow native platform conventions.
- File pickers, browser launching, credential storage, and cloud integration
  may use platform-native APIs.
- A platform limitation must be documented here before it creates an observable
  behavior difference.

## Backup

HistoryLib does not expose a backup feature. User-initiated export remains a
data portability operation, not an automatic backup service. Platform sync is
a separate feature and must not be described as backup.
