# HistoryLib

English | [简体中文](README.zh-CN.md)

HistoryLib is a SwiftUI app for collecting, browsing, searching, deduplicating,
and re-exporting browser history records. It currently focuses on Safari
history export files and HistoryLib's own `.hlz` archive format.

Imported records are stored with SwiftData. The app can use CloudKit for iCloud
sync, and can export large datasets as a ZIP-based `.hlz` archive with JSONL
chunks and validation indexes.

## Status

This project is early and personal-use oriented. The app is usable enough to
import, browse, summarize, export, and deduplicate history data, but the public
API, archive format details, and UI may still change.

Browser history is sensitive personal data. Do not publish exported `.hlz`,
`.zip`, or `.json` history files unless you have reviewed their contents.

## Features

- Import Safari history JSON files, folders, and ZIP archives.
- Import HistoryLib `.hlz` archives.
- Browse records by year, month, and day.
- Search by URL or title.
- Open records in the system browser.
- Show cached site favicons.
- Generate summary snapshots.
- Export Safari-compatible ZIP archives.
- Export optimized HistoryLib `.hlz` archives.
- Deduplicate imported or synced records.
- Sync records and app settings with iCloud when enabled.

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
[ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9.20.

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

- [Project documentation](Documentation.docc/Documentation.md)
- [Archive format](Documentation.docc/HistoryLib-Archive-Format.md)
- [Privacy and data](Documentation.docc/Privacy-and-Data.md)
- [Project structure](Documentation.docc/Project-Structure.md)
- [Development notes](Documentation.docc/Development.md)

## License

HistoryLib is licensed under the MIT License. See [LICENSE](LICENSE).

Third-party dependency notices are listed in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
