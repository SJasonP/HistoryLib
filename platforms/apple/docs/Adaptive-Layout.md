# Adaptive Layout and iPhone Duo

HistoryLib builds with the iOS 27.1 SDK while retaining its iOS 26 deployment
target. No device-model checks or full-screen restrictions are needed.

## Implementation

- iOS uses one stable `TabView` with system navigation stacks and toolbars.
  The adaptable tab style prefers a sidebar where the system supports it.
  iOS 27 uses `defaultTabBarPlacement`; iOS 26 uses the earlier placement API.
  The system handles vertical controls, camera insets, and RTL placement.
- The library uses compact-width drill-down and regular-width expandable
  groups. A value-based year route and a navigation path owned by `ContentView`
  retain drill-down navigation when the root list changes its layout.
- Search is attached to the same library navigation stack at every size.
  The existing phone-specific direct-results preference stays consistent across
  displays. A new search returns to the library root to avoid an obsolete year
  destination hiding the results.
- Transfer progress is scrollable so cancellation remains reachable in short
  windows and at large text sizes. On iOS 27.1, the overlay uses the system's
  `ArrangementView` to accommodate the fold. Earlier systems retain a centered,
  scrollable presentation. Only the dimming background ignores safe areas.
- Transfer state remains owned by the root view. Real root disappearance still
  cancels tasks; changes to window size do not introduce a new cancellation path.

## Automated Verification

From this directory's parent (`platforms/apple`):

```sh
xcodebuild -project HistoryLib.xcodeproj -scheme HistoryLib \
  -destination 'platform=iOS Simulator,name=iPhone Duo' \
  -parallel-testing-enabled NO \
  -only-testing:HistoryLibTests \
  -only-testing:HistoryLibUITests/HistoryLibUITests \
  test CODE_SIGNING_ALLOWED=NO
```

If multiple simulators share the same name, select a specific simulator UUID.
The UI tests cover search results/query retention, export password retention,
and library navigation across rotation. Each test launches directly into its target tab so it does not depend on
the system's tab-bar/sidebar accessibility representation. The debug-only launch flag creates an in-memory store of fictional
`example.com` records; Release builds contain no fixture-store entry point.
The flag is `HISTORYLIB_UI_TESTING=1`, and does not open the normal database.

The shared localization validator remains:

```sh
python3 shared/localization/validate_localizations.py
```

Run that command from the repository root. UI tests do not establish physical
hinge behavior or replace interactive acceptance.

## Validation Record (October 18, 2026)

- Xcode 27.1 / iOS 27.1 SDK; deployment target remains iOS 26.
- Unsigned iOS device Release build passed. The Release executable contains
  neither the UI-test launch flag nor the synthetic fixture strings.
- macOS Debug build passed.
- All 38 data-path tests passed. An initial run also passed three UI rotation
  regressions (41 tests total). Test runs emitted background-thread publication
  warnings; this layout change does not establish their cause.
- Six-language localization validation passed.
- After improving password assertions and making UI-test launches independent
  of sidebar selectors, the latest UI rerun could not finish: the simulator
  launcher reported `NSMachErrorDomain -308 (server died)`, and its destination
  subsequently became unavailable. Do not treat that rerun as a pass.
- Interactive acceptance, including partial folds, Split View, RTL, large text,
  and long-running transfer continuity, remains with the human maintainers.

## Human Acceptance

Interactive simulator and physical-device acceptance are owned by the human
maintainers. Check these before declaring the release verified on Duo:

1. Open/close/partially fold while searching, browsing a year/month/day, and
   scrolling a long list. Check the selected tab, query, navigation, directory
   expansion, and visible position.
2. Open/close while editing an export password or importing an encrypted archive.
   Check that the password sheet remains usable and input is retained.
3. Change pose during a long import/export. Verify progress remains visible,
   cancellation is reachable, tasks do not restart, and completion presents the
   result or document picker normally.
4. Test each side of Split View, landscape on the outer display, the software
   keyboard, large accessibility text, Arabic RTL, and dark appearance.
5. Recheck ordinary iPhone and iPad navigation/search, plus iOS 26 fallback UI.

SDK guidance: [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/).
