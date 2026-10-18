# HistoryLib

[简体中文](README.zh-CN.md)

HistoryLib is a native, multi-platform application for importing, browsing,
searching, deduplicating, syncing, and exporting browser history.

Version 1.4 is being developed as the first coordinated Apple, Android, and
Windows release. Each client uses its platform's native language and UI stack;
shared specifications and fixtures keep behavior and data formats compatible.

All clients target the six United Nations official languages: American
English, Simplified Chinese, Arabic, French, Russian, and Spanish. Arabic uses
native right-to-left layout, and count-sensitive text follows each platform's
plural rules.

## Repository layout

- `platforms/apple`: Swift, SwiftUI, SwiftData, and CloudKit client.
- `platforms/android`: Kotlin and Jetpack Compose client targeting API 36+.
- `platforms/windows`: C# and WinUI 3 client placeholder.
- `shared/specs`: cross-platform behavior and format contracts.
- `shared/fixtures`: synthetic interoperability and rejection fixtures.

The repository has one Git history and one product version. Platform build
numbers can differ, but public feature versions must remain aligned.

Shared specifications are indexed in [`shared/specs/README.md`](shared/specs/README.md).

## Current status

- Apple 1.3 is the current completed client.
- Android 1.4 has a functional native client and is in release-hardening.
- Windows 1.4 is planned.

See each platform directory for platform-specific build instructions.

The detailed Android 1.4 product and implementation baseline is available in
[`platforms/android/docs/Android-1.4-Specification.zh-CN.md`](platforms/android/docs/Android-1.4-Specification.zh-CN.md).

## Privacy

Browser history is sensitive personal data. Do not commit real browsing data to
this repository. HistoryLib does not expose a product-level backup feature;
exports are explicit, user-initiated data transfers.

## License

HistoryLib is released under the MIT License. See `LICENSE`.
