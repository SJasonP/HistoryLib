# Search

Apple v1.4 supports keyword search and manual advanced filters. Apple
Intelligence interpretation and AI-backed Siri search are disabled. A keyword
App Shortcut remains available; it opens the app rather than returning history
records to the system. This page describes search and the boundary for future
intelligence integration.

## User experience

When **Advanced Search** is enabled in Settings, open Library/Search and choose
**Search Filters**. Edit the terms, domain, browser, and dates directly, then
choose **Search**. Each term occupies one line; a line can contain a literal
multiword phrase. All terms must match. When the preference is disabled, the
Library keeps the ordinary keyword search field and searches URL/title text
directly.

Active advanced filters remain visible through **Review Filters** and
**Clear Filters**. Typing in the ordinary search field adds a literal term to
those filters. Clearing advanced filters does not erase ordinary search text.

AI, Siri, and Shortcuts status:

- No AI-backed Siri or Shortcuts search action is exposed by the production
  build.
- The keyword search field and manually edited advanced filters are unaffected
  by this disabled integration.
- A future reactivation must keep generated filters editable and require an
  explicit user action before querying history.

The current manual search UI is localized in the six product languages. Any
future intent descriptions or app shortcut phrases must follow the same
localization requirement; model and system-language availability are separate
from resource completeness.

## Architecture and data boundary

`HistorySearchFilter` validates and matches structured values.
`HistorySearchEngine` narrows dates in SwiftData, scans in bounded chunks, yields
between chunks, and keeps every match in a fetched chunk. View generations stop
stale/cancelled pages from being published after a filter change. Search errors
use generic messages rather than exposing URLs or low-level database errors.

If reactivated in a future release, `NaturalLanguageHistorySearch` must use
`SystemLanguageModel.default`, never
`PrivateCloudComputeLanguageModel` or third-party providers. A new session is
created per interpretation. Only the request, local reference day/time zone,
and fixed instructions are passed to it. Generated output is validated as a
filter; it is never executed as SQL or a predicate string. The parser supports
at most 2,000 characters per request, sixteen filter terms, 2,000 characters per
term, and 4,000 term characters in total. Inference output is bounded to 512
tokens. Model errors and prompt contents are not logged.

If the future integration is reactivated, `HistorySearchRequests` is intended to
remain an in-memory foreground handoff. Intent execution must require local
authentication. It must store no query in preferences, files, notifications,
URL schemes, or the archive format. Cold-start and busy-state requests must be
consumed once; the latest queued request must replace older ones.
There is no database-reading App Intent or separate intent extension, preventing
an extra persistence container from opening with a divergent sync setting.

The initial release does not populate system history indexes or expose record
entities. Siri itself is a system service: the application's on-device model
choice does not imply that every Siri request is processed locally by Apple.
See the shared [search contract](../../../shared/specs/search.md).

## Availability and fallback for a future capability

The app retains its iOS/macOS 26 deployment targets. Manual filters work on
that baseline. If the future capability returns, device eligibility, downloaded
model state, supported languages, and system region policies may prevent
inference or Siri AI from working; manual filters must remain available.

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

## Human acceptance

Humans own simulator interaction and visual checks. For the current release,
also verify that disabled AI/Siri controls and actions are absent:

1. Keyword and manual structured searches on supported Apple devices. Include
   dates, domain restrictions, multiple terms, each supported query language,
   empty results, and cancellation.
2. Confirm that the AI/Siri controls, production natural-language shortcut, and
   system search schema are absent while manual filters remain usable.
3. Check macOS, compact/regular iOS layouts, Duo resizing, keyboard, large text,
   Arabic RTL, cancellation, and all six UI languages.

Primary API references:
[Apple Intelligence](https://developer.apple.com/apple-intelligence/),
[system search schema](https://developer.apple.com/documentation/appintents/appschema/systemintent/searchinapp),
[advanced App Intents](https://developer.apple.com/videos/play/wwdc2026/343/).
