# HistoryLib

English | [简体中文](README.zh-CN.md)

HistoryLib is a SwiftUI app for collecting, browsing, searching, deduplicating,
and re-exporting browser history records. It currently focuses on Safari
history export files, Chrome history exported through Google Takeout, and
HistoryLib's own `.hlz` archive format.

Imported records are stored with SwiftData. The app uses the system iCloud
settings to control CloudKit synchronization and can export large datasets as
a ZIP-based `.hlz` archive with JSONL chunks and validation indexes.

## Status

The Apple client is the v1.4 release target. The public archive format is
versioned in `shared/specs`; platform UI and implementation details may evolve.

Browser history is sensitive personal data. Do not publish exported `.hlz`,
`.zip`, or `.json` history files unless you have reviewed their contents.

## Features

- Import Safari history JSON files, folders, and ZIP archives.
- Import Chrome history from a Google Takeout export (JSON, folder, or ZIP).
- Import HistoryLib `.hlz` archives.
- Browse records by year, month, and day.
- Search by URL or title.
- Open records in the system browser.
- Show cached site favicons.
- Generate summary snapshots.
- Export Safari-compatible ZIP archives.
- Export optimized HistoryLib `.hlz` archives.
- Deduplicate imported or synced records.
- Sync records and app settings with iCloud when permitted by system settings.

## Platforms

- iOS
- macOS

The current deployment targets in the project are iOS 26.x and macOS 26.x.

## Requirements

- Xcode with Swift, SwiftUI, SwiftData, and CloudKit support for the configured
  deployment targets.
- An Apple Developer team and valid iCloud entitlements if you want CloudKit
  sync to work on devices.
- Network access for package resolution and favicon fetching.

The project uses Swift Package Manager and currently depends on
[ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9.20 and
[Swift Sodium](https://github.com/jedisct1/swift-sodium), which bundles
libsodium for password-protected `.hlz` archives.

## Build

Open `HistoryLib.xcodeproj` in Xcode and run the `HistoryLib` scheme.

From the command line:

```sh
xcodebuild -list -project HistoryLib.xcodeproj
xcodebuild -project HistoryLib.xcodeproj -scheme HistoryLib build
```

For simulator or device builds, pass a destination that matches your local
Xcode installation, for example:

```sh
xcodebuild \
  -project HistoryLib.xcodeproj \
  -scheme HistoryLib \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

## Test

Run tests from Xcode or use `xcodebuild`:

```sh
xcodebuild \
  -project HistoryLib.xcodeproj \
  -scheme HistoryLib \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```

## Documentation

- [Changelog](../../CHANGELOG.md)
- [Intelligent search, Siri, and Shortcuts](docs/Intelligent-Search.md)
- [Adaptive layout and iPhone Duo](docs/Adaptive-Layout.md)
- [Project documentation](Documentation.docc/Documentation.md)
- [Shared archive format](../../shared/specs/hlz-v1.md)
- [Shared specifications](../../shared/specs/README.md)
- [Privacy and data](Documentation.docc/Privacy-and-Data.md)
- [Project structure](Documentation.docc/Project-Structure.md)
- [Development notes](Documentation.docc/Development.md)

## License

HistoryLib is licensed under the MIT License. See [LICENSE](../../LICENSE).

Third-party dependency notices are listed in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
