# Intelligent Search, Siri, and Shortcuts

## User experience

Open Library/Search and choose **Search Filters**. Enter a natural-language
request, then choose **Interpret on Device**. Review and edit the proposed
terms, domain, browser, and dates before choosing **Apply Filters**. You can
also fill in the filters directly without a model. Each term occupies one
line; a line can contain a literal multiword phrase. All terms must match.

Active advanced filters remain visible through **Review Filters** and
**Clear Filters**. Typing in the ordinary search field adds a literal term to
those filters. Clearing advanced filters does not erase ordinary search text.

Siri/Shortcuts actions:

- **Search History** opens keyword results in the application.
- **Prepare Natural Language Search** opens the editor with the spoken/requested
  text; interpretation and application remain explicit user actions.
- On iOS/macOS 27, the `.system.searchInApp` schema provides the standard Siri
  application-search integration. It searches literal text; it does not claim
  to implement unrestricted semantic or conversational retrieval.

All UI copy, intent descriptions, and app shortcut phrases are localized in the
six product languages. Model and system-language availability are separate from
resource completeness.

## Architecture and data boundary

`HistorySearchFilter` validates and matches structured values.
`HistorySearchEngine` narrows dates in SwiftData, scans in bounded chunks, yields
between chunks, and keeps every match in a fetched chunk. View generations stop
stale/cancelled pages from being published after a filter change. Search errors
use generic messages rather than exposing URLs or low-level database errors.

`NaturalLanguageHistorySearch` uses `SystemLanguageModel.default`, never
`PrivateCloudComputeLanguageModel` or third-party providers. A new session is
created per interpretation. Only the request, local reference day/time zone,
and fixed instructions are passed to it. Generated output is validated as a
filter; it is never executed as SQL or a predicate string. The parser supports
at most 2,000 characters per request, sixteen filter terms, 2,000 characters per
term, and 4,000 term characters in total. Inference output is bounded to 512
tokens. Model errors and prompt contents are not logged.

`HistorySearchRequests` is an in-memory foreground handoff. Intent execution
requires local authentication. It stores no query in preferences, files,
notifications, URL schemes, or the archive format. Cold-start and busy-state
requests are consumed once; the latest queued request replaces older ones.
There is no database-reading App Intent or separate intent extension, preventing
an extra persistence container from opening with a divergent sync setting.

The initial release does not populate system history indexes or expose record
entities. Siri itself is a system service: the application's on-device model
choice does not imply that every Siri request is processed locally by Apple.
See the shared [search contract](../../../shared/specs/search.md).

## Availability and fallback

The app retains its iOS/macOS 26 deployment targets. Conventional intents and
manual filters work on that baseline; the new system search schema is gated to
27. Device eligibility, whether Apple Intelligence is enabled, downloaded model
state, supported languages, and system region policies can prevent inference or
Siri AI from working. The app checks model availability and leaves manual
filters available. Inference failures preserve the editor contents and expose
a localized, non-sensitive error.

## Automated verification

`HistorySearchTests` covers hostile/lookalike domain boundaries, case-insensitive
AND matching, browser filters, half-open dates, local DST days, malformed model
output, pagination without skipped records, cancellation, and queued requests.
`HistorySearchIntentTests` executes the intent implementations against the
in-memory router. These do not invoke Siri or the device language model.

For hosted unit tests, set `HISTORYLIB_TESTING=unit` in the test host's launch
environment. Debug builds then create an empty, in-memory store and render an
empty host view; they do not initialize the normal store or consume routed
intent requests. This mode is excluded from Release. The separate
`HISTORYLIB_UI_TESTING=1` mode retains the fictional records used by UI tests.

From `platforms/apple`, run:

```sh
./scripts/test-unit.sh 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID'
```

The script builds test products, injects the isolated host environment into the
unit-test target's generated `.xctestrun`, and runs only `HistoryLibTests`.
`HISTORYLIB_TEST_DERIVED_DATA` can select a reusable build directory. With no
argument, the script selects an iPhone Duo by name; use an ID when names are
ambiguous. Run the shared localization validator from the repository root too.

## Validation record (October 18, 2026)

- iOS 27.1 simulator test build passed for arm64 and x86_64.
- 46 hosted unit/integration tests passed, with no failures, skips, or runtime
  warnings. The suite includes all 38 existing data-path tests and eight new
  filter, model-output validation, paging, cancellation, routing, and intent tests.
- Unsigned iOS device Release and macOS Debug builds passed.
- Release App Intents metadata contains all three foreground actions with local
  authentication required, including the system search schema gated to 27.
- Release shortcut language models were generated for all six locales. String
  catalog coverage and shortcut application-name placeholders passed validation.
- Release binary inspection found no unit/UI-test environment keys or synthetic
  fixture strings. The isolated test script completed successfully;
  `git diff --check` and shell syntax validation passed.
- No interactive simulator/physical-device acceptance, actual on-device model
  inference, or end-to-end Siri invocation was performed. Those remain human
  acceptance tasks below.

## Human acceptance

Humans own simulator interaction, visual checks, model behavior, and real Siri
acceptance. Check these in addition to automated tests:

1. Keyword, manual, and natural-language searches on supported Apple devices.
   Include dates such as last month, domain restrictions, multiple terms, each
   supported query language, unsupported requests, disabled AI, and model errors.
2. Review generated conditions before applying. Check that invalid proposals do
   not overwrite existing filters or execute a query. Compare returned records
   to the visible conditions; no matching records is a valid result.
3. Invoke both actions from Shortcuts and Siri, including cold launch, locked
   device, repeated requests, and requests during transfers or document/password
   sheets. Confirm that record details are not spoken or returned to Siri.
4. Check the system `.searchInApp` action on 27 separately from conventional
   shortcuts on 26. Compilation and direct `perform()` tests do not establish
   that the OS recognizes phrases or that Siri AI is available in a region.
5. Check macOS, compact/regular iOS layouts, Duo resizing, keyboard, large text,
   Arabic RTL, cancellation, and all six UI languages.

Primary API references:
[Apple Intelligence](https://developer.apple.com/apple-intelligence/),
[system search schema](https://developer.apple.com/documentation/appintents/appschema/systemintent/searchinapp),
[advanced App Intents](https://developer.apple.com/videos/play/wwdc2026/343/).
