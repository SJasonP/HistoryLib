# HistoryLib

[简体中文](README.zh-CN.md)

HistoryLib is a native, multi-platform application for importing, browsing,
searching, deduplicating, syncing, and exporting browser history.

Version 1.4 will ship only for Apple platforms (iOS and macOS). Android and
Windows releases are deferred; their source remains in this repository for
future work. Native clients share behavior contracts and synthetic fixtures.

All clients target the six United Nations official languages: American
English, Simplified Chinese, Arabic, French, Russian, and Spanish. Arabic uses
native right-to-left layout, and count-sensitive text follows each platform's
plural rules.

## Repository layout

- `platforms/apple`: Swift, SwiftUI, SwiftData, and CloudKit client.
- `platforms/android`: Kotlin and Jetpack Compose client targeting API 36+.
- `platforms/windows`: C# and WinUI 3 client sources, not included in v1.4.
- `shared/specs`: cross-platform behavior and format contracts.
- `shared/fixtures`: synthetic interoperability and rejection fixtures.

The repository has one Git history and one product version. Platform build
numbers can differ. Released clients use the product version; deferred clients
are not claimed as released or fully compatible.

Shared specifications are indexed in [`shared/specs/README.md`](shared/specs/README.md).

## Current status

- Apple 1.4 is being prepared for security audit and release.
- Android and Windows are development clients; their releases are deferred.
- See the [Apple release-readiness record](platforms/apple/docs/Release-1.4.md)
  for checks and remaining human acceptance gates.

See each platform directory for platform-specific build instructions.

The detailed Android 1.4 product and implementation baseline is available in
[`platforms/android/docs/Android-1.4-Specification.zh-CN.md`](platforms/android/docs/Android-1.4-Specification.zh-CN.md).

## Privacy

Browser history is sensitive personal data. Do not commit real browsing data to
this repository. HistoryLib does not expose a product-level backup feature;
exports are explicit, user-initiated data transfers.

## License

HistoryLib is released under the MIT License. See `LICENSE`.
