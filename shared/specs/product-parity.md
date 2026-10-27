# Product Parity Contract

Status: shared baseline for native clients; v1.4 ships Apple only

The Android implementation baseline is documented in
`platforms/android/docs/Android-1.4-Specification.zh-CN.md`.

## Release rule

Apple v1.4 ships for iOS and macOS only. Android and Windows are deferred.
The requirements below remain the target behavior for native clients, but an
unreleased client does not block the Apple release. Apply these gates to every
client included in a future coordinated release. See `versioning-and-release.md`.

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
- Ship all six product languages defined in `localization.md`.
- Protect the history library before usable content is shown: use the platform
  system App Lock where it exists, and provide a default-on app-owned privacy
  lock on desktop platforms without an equivalent system feature.

Sync follows `sync.md`: HistoryLib 1.4 uses platform-local sync, and a
platform may document that it ships without sync when platform-local sync is
technically impractical. Such a platform must expose an explicit unsupported
state and must not claim parity for sync.

Documented Android development limitation: Android has no sync and exposes an explicit
unsupported state (see `platforms/android/docs/Android-1.4-Specification.zh-CN.md`).

## Allowed platform differences

- Visual design language, navigation components, menus, dialogs, and adaptive
  layouts may follow native platform conventions.
- File pickers, browser launching, credential storage, and cloud integration
  may use platform-native APIs.
- A platform limitation must be documented here before it creates an observable
  behavior difference.

The privacy-lock implementation differs by platform: iOS/iPadOS use the
system Lock App feature; macOS and Windows use native local authentication
with an app setting that defaults to enabled; Android may use a device or
manufacturer privacy container and must document when that protection is not
available.

## Backup

HistoryLib does not expose a backup feature. User-initiated export remains a
data portability operation, not an automatic backup service. Platform sync is
a separate feature and must not be described as backup.
