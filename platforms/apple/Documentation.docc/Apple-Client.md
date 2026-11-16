# Apple Client

English | [简体中文](Apple-Client.zh-CN.md)

HistoryLib organizes imported browser history on iPhone, iPad, and Mac.
The app uses SwiftUI for its interface, SwiftData for local storage, and
CloudKit for iCloud synchronization.

## Import and export

Import Safari history, Google Takeout Chrome history, and HistoryLib archives
from supported files, folders, or ZIPs. The app detects the format and merges
duplicate records.

Export as Safari, Google Takeout, or HistoryLib `.hlz`. Native archives can
be password-protected. Exports provide data portability; whether a browser can
import them depends on that browser's supported formats.
See <doc:HistoryLib-Archive-Format> for the native format.

## Browse and search

Library groups records by year, month, and day. Keyword search matches titles
and URLs. Advanced Search adds editable terms, domain, browser, and date
filters; it is off by default. AI interpretation and Siri AI search are disabled.

Record taps/clicks can open the browser, copy the full URL, or do nothing.
Long-press and right-click menus also provide record actions. Deletion actions
require the corresponding setting.

Summary shows saved records, stored visit totals, active days, date coverage,
monthly activity, and browser/site rankings.

## Storage and privacy

Core history browsing and management work offline. Normal iCloud sync follows
system settings. Manage displays storage usage, observed sync activity, and
local/cloud record counts. Sync is not a backup.

macOS has a default-on privacy lock using native authentication. iPhone and iPad
use Apple's system app-locking feature. Optional website icons contact the
corresponding sites. See <doc:Privacy-and-Data> and <doc:Version-Compatibility>.

## Support and requirements

The app is free, open source, and ad-free. Voluntary tips support the developer
without unlocking features. Help links to GitHub Issues and private email.

The minimum supported systems are iOS/iPadOS 26 and macOS 26. The interface
supports English, Simplified Chinese, Arabic, French, Russian, and Spanish.

## Development

Build and test instructions are in <doc:Development>. Code organization is
described in <doc:Project-Structure>, and dependency notices are in
<doc:THIRD-PARTY-NOTICES>. Shared contracts are indexed
[here](../../../shared/specs/README.md), and changes are recorded in the
[Changelog](../../../CHANGELOG.md).
