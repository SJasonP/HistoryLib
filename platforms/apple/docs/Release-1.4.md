# Apple v1.4 release preparation

Status checked on **2026-10-26**. This is an audit candidate, not a release
approval or publication record. The release includes **iOS and macOS only**;
Android and Windows are deferred. Minimum supported OS versions remain 26.0.
The Apple app is configured as **1.4 (8)**, following v1.3 (7).

## Engineering status

The preflight branch is `codex/apple-v1.4-preflight`. Its ancestry includes the
completed adaptive-layout, structured-search, optional Foundation Models, and
authenticated Siri/Shortcuts work. See [the changelog](../../../CHANGELOG.md)
for the prepared user-facing changes.

The preflight fixes and housekeeping are complete:

- Align Apple marketing/build versions and the Apple-only release contract.
- Block history mutations when persistent storage fails and recovery is only
  in memory, including when iCloud is disabled. Show a localized explanation.
- Fetch favicons using only the recorded site's origin; strip recorded paths,
  queries, fragments, and credentials, reject off-origin discovered icons,
  avoid HTTPS downgrades, and retain the existing redirect rejection.
- Complete ZIP-limit errors and storage-recovery messages in all six languages.
  Preserve the existing String Catalog extraction changes.
- Bundle an app privacy manifest and check the final Release resources,
  exported actions, local authentication policy, and absence of debug fixtures.
- Use the resolved package versions for the isolated unit-test build.

No additional feature work is required for this release's stated scope.
Security findings and acceptance failures may still require changes.

## Verification evidence

Performed against this candidate, using fictional test data:

| Check | Result |
| --- | --- |
| iOS generic-device Release build, unsigned | Passed |
| macOS Release build, unsigned | Passed |
| Isolated iOS Simulator unit/integration suite | 49 passed, 0 failed, 0 skipped |
| Test-result runtime warnings | None |
| Six-language resource validator | Passed |
| Final iOS and macOS Release structure checks | Passed |
| SwiftData model source versus v1.3 | `Item.swift` and `SummarySnapshot.swift` unchanged |

The simulator suite is automated; no interactive or visual simulator acceptance
was performed. Build logs contain Xcode SDK-build telemetry diagnostics, three
existing immutable-variable suggestions in intent tests, and a test-target
App Intents extraction warning. They did not fail builds/tests; application
Release metadata contains all three expected authenticated foreground actions.

Reproduce from the repository root:

```sh
python3 shared/localization/validate_localizations.py
HISTORYLIB_TEST_DERIVED_DATA=/tmp/historylib-v14-tests \
  platforms/apple/scripts/test-unit.sh '<iOS Simulator destination>'
xcodebuild -project platforms/apple/HistoryLib.xcodeproj -scheme HistoryLib \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath /tmp/historylib-v14-ios \
  -onlyUsePackageVersionsFromResolvedFile build CODE_SIGNING_ALLOWED=NO
xcodebuild -project platforms/apple/HistoryLib.xcodeproj -scheme HistoryLib \
  -destination 'platform=macOS' -configuration Release \
  -derivedDataPath /tmp/historylib-v14-macos \
  -onlyUsePackageVersionsFromResolvedFile build CODE_SIGNING_ALLOWED=NO
python3 platforms/apple/scripts/check-release.py \
  '/tmp/historylib-v14-ios/Build/Products/Release-iphoneos/History Lib.app'
python3 platforms/apple/scripts/check-release.py \
  '/tmp/historylib-v14-macos/Build/Products/Release/History Lib.app'
```

Replace the simulator destination with an installed device identifier. Test
execution uses the DEBUG in-memory test host, not the user's history store.
Unsigned builds and structural checks do not establish distribution acceptance.

## Privacy manifest and dependency baseline

The app declares no tracking or developer-collected data in its manifest.
This does not replace store privacy answers: optional CloudKit and origin-only
favicon requests are described in the privacy documentation and must be reviewed.
Required-reason APIs declare:

- `CA92.1`: app-only UserDefaults.
- `C617.1` and `3B52.1`: metadata of app-container and user-selected files.
- `E174.1`: available disk space used to reject imports that cannot safely fit.

These uses follow Apple's [required-reason API definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)
and [manifest guidance](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).
ZIPFoundation's own privacy manifest is also present in both built apps.

The checked-in `Package.resolved` pins ZIPFoundation 0.9.20 at
`22787ffb59de99e5dc1fbfe80b19c97a904ad48d` and swift-sodium at
`cfd195c76882aa9b997560ca7cb95d72fbf5db00`. Audit their resolved sources and
the libsodium binary dependency as well as first-party code. No dependency
upgrade was silently combined with this release preparation.

## Security audit handoff

The security audit has **not started**. Use the final preflight commit as the
candidate revision and v1.3 as the comparison baseline. The runtime scope is
`platforms/apple`, its pinned dependencies, and the shared contracts,
localizations, and fixtures used by Apple. Android and Windows runtime code is
outside this release's audit scope.

Review especially untrusted Safari/Takeout/HLZ import and extraction, encrypted
archive handling, temporary-file cleanup, persistent-store failure behavior,
CloudKit boundaries, favicon networking, model prompt/output validation, Siri
authentication/data exposure, and Release test-hook exclusion. These are audit
targets, not assertions that a vulnerability exists or that an audit passed.
Re-run relevant checks after fixes; audit the final source revision before tagging.

## Remaining acceptance and distribution gates

Human interactive acceptance remains outstanding and is owned by the maintainers:

- Upgrade an actual v1.3 store; compare history/counts and verify import/export,
  encrypted HLZ interoperability, deletion, restart, and recovery behavior.
  Unchanged model source alone does not prove migration or data preservation.
- Verify iCloud on/off and relaunch behavior, account/network failures, sync
  between devices, and the CloudKit production schema/environment.
- Check iPhone, iPad, macOS, and Duo compact/expanded/rotated layouts, keyboard,
  transfer progress/cancel, navigation continuity, large text, and Arabic RTL.
- Exercise actual on-device interpretation, unavailable/disabled-model fallback,
  and Siri/Shortcuts end to end on supported OS versions. The 27 search schema
  does not provide a history entity index or general screen-awareness feature.
- Verify that the Help page's existing Helper link can be opened publicly and
  its intended downloads are accessible. Its public URL returned HTTP 200;
  page permissions/content and download availability were not established by
  that transport-level check.

After audit fixes and acceptance, prepare signed distribution archives and run
Xcode/store validation. Confirm provisioning, production entitlements, build-number
availability, store privacy answers, export-compliance answers, screenshots, and
release notes. Distribution validation/upload has not been performed here.
Do not create `v1.4`, upload, or publish until those gates pass and publication
is authorized. No release tag, upload, or publication was made during preflight.
