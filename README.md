# HistoryLib

English | [简体中文](README.zh-CN.md)

HistoryLib gives your browser history a place of its own. Import records from
Safari, Google Takeout, or a HistoryLib archive, then browse, search, and organize
them without importing everything back into a browser.

The Apple app is free to use, open source, and ad-free. Optional tips support the
developer and do not unlock features.

> This is a vibe coding project. AI has done most of the work. If that concerns
> you, please do not use this project. For problems or suggestions, please open
> an Issue first rather than submitting a pull request directly.

## Features

- **Import your history:** recognize supported files, folders, and ZIP archives
  automatically, and merge duplicate records.
- **Find a page again:** browse by year, month, and day, search titles and URLs,
  or enable Advanced Search for terms, domain, browser, and date filters.
- **See the bigger picture:** view activity by month, browser and site rankings,
  date coverage, and the difference between saved records and visit totals.
- **Keep records across Apple devices:** sync history and settings through
  iCloud when permitted by system settings.
- **Take your data with you:** export Safari, Google Takeout, or HistoryLib
  `.hlz` files. Native archives support optional password protection.
- **Choose how records open:** open a page in your browser, copy its full URL,
  or leave clicks inactive. Context menus provide quick record actions.

Core history browsing and management work offline. Sync, site icons, and
in-app purchases use network services.

## Platforms

Version 1.4 focuses on iPhone, iPad, and Mac, with iOS/iPadOS 26 and macOS 26
as the minimum supported systems. Android and Windows clients are under
development and are not included in this release.

The Apple interface supports English, Simplified Chinese, Arabic, French,
Russian, and Spanish.

## Get started

Import an export from your browser in **Manage**, find records in **Library**,
and explore your activity in **Summary**. HistoryLib archives let you move
records between compatible installations.

See [Releases](https://github.com/SJasonP/HistoryLib/releases) for published
versions and the [Changelog](CHANGELOG.md) for changes.

To build from source, start with the
[Apple development guide](platforms/apple/Documentation.docc/Development.md).
Android and Windows build instructions are in their platform directories.

## Repository

| Directory | Contents |
| --- | --- |
| [`platforms/apple`](platforms/apple) | SwiftUI app, SwiftData storage, CloudKit integration, and Apple documentation |
| [`platforms/android`](platforms/android) | Android client built with Kotlin and Jetpack Compose |
| [`platforms/windows`](platforms/windows) | Windows client built with C# and WinUI 3 |
| [`shared/specs`](shared/specs/README.md) | Product behavior, archive formats, and compatibility contracts |
| [`shared/fixtures`](shared/fixtures/README.md) | Synthetic data for import, export, and compatibility tests |

Each client uses native platform tools. Shared specifications and fixtures
define the data formats and behavior they implement.

## Privacy and feedback

History is stored on your device and may sync through your iCloud account.
Optional site icons contact the corresponding websites. Exported files contain
your browsing history; keep them private.
See [Privacy and Data](platforms/apple/Documentation.docc/Privacy-and-Data.md)
for details.

Report bugs or suggest improvements through
[GitHub Issues](https://github.com/SJasonP/HistoryLib/issues).
For private feedback, email [SJasonP@iCloud.com](mailto:SJasonP@iCloud.com).
Use fictional or redacted data when reporting a problem.

## License

Distributed under the [MIT License](LICENSE), without warranty.
Apple dependency notices are available [here](platforms/apple/Documentation.docc/THIRD-PARTY-NOTICES.md).
