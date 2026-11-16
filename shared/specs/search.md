# Search and Optional Intelligence

Status: Apple enhancement; other clients retain their existing keyword search.
This is an optional Apple capability. Android and Windows are deferred from v1.4.

Apple Intelligence interpretation and AI-backed Siri search are disabled by the
Apple client feature flag. A keyword App Shortcut remains available and opens
the app without returning history records to the system. Manual structured
filters remain available whenever Advanced Search is enabled.

## Advanced search preference

Apple clients expose an `Advanced Search` setting that is disabled by default.
When it is disabled, tapping the search field opens the ordinary keyword search
experience and typing searches the URL and title directly. Advanced filters and
the standalone filter page remain hidden.

When it is enabled, the standalone search page exposes structured filters that
the user can edit and apply manually. The Apple Intelligence and Siri layer is
disabled in the current Apple release, so enabling this preference does not
enable AI, Siri, or Shortcuts integration. The default presentation remains the
existing direct-results experience.

## Structured search

Apple keyword search and advanced-search text inputs expose a clear button
when nonempty. Clearing affects only that input, using the same search update
behavior as deleting its text manually. Password inputs also offer clearing
while keeping their contents masked.

A filter can contain literal terms, a domain, a source browser, and visit-time
bounds. All constraints are ANDed. Each literal term must occur in the URL or
title, using locale-aware case-insensitive matching. Terms are not executable
queries, regular expressions, SQL, or model-generated predicates.

- A domain matches that exact hostname or a subdomain separated by a dot.
  A suffix lookalike, a path containing the name, or a URL username does not
  match. Scheme, path, port, query, and user-info are not accepted as domains.
- The current browser choices are Safari, Chrome, or no browser restriction.
- Visit-time intervals include their start and exclude their end.
- Calendar-day controls include the selected final day, using the user's local
  calendar and time zone. Do not add a fixed 86,400 seconds across DST changes.
- Terms and domains are normalized and validated before query execution.
- An empty structured filter clears the advanced restrictions. Ordinary text
  entered in the search bar adds another literal term to active filters.
- Paging must not discard matches at chunk boundaries. Reset cursors when
  filters or text change. Cancelled/stale pages must not replace newer results.
- Queries never mutate history, counts, snapshots, or deduplication keys.

## Natural language (future Apple capability)

The natural-language design is documented here for a future opt-in Apple
capability. It is not active in the current release. If enabled in a future
release, the implementation must use the on-device Foundation Models system
model and receive only the user's request, reference date/time zone, and fixed
parsing instructions. No history entries, URLs, titles, passwords, archive
content, database schema, or retrieval tools may be supplied to the model.

Any future generated output must be a proposed structured filter. Unsupported
requests, invalid dates/domains, unsupported browsers, and empty proposals must
be rejected. The user must review and apply the editable proposal before it
queries the history store.

Manual filters and keyword search are the current supported behavior. If this
capability returns in a future release, model availability and language support
will vary, and interpretation failure must not silently substitute a keyword
search or clear a previously edited filter.

This feature does not infer webpage bodies, generate visit records, reconstruct
actual navigation links, or guarantee semantic recall from missing content.

## AI-backed Siri and Shortcuts (disabled)

The current Apple release exposes no AI-backed Siri or Shortcuts search
integration. The production natural-language preparation action and system
application-search schema are disabled. Ordinary in-app keyword search and
manually edited advanced filters remain available.

If Siri or Shortcuts integration is re-enabled in a future release, requests
must remain bounded and in memory, require local device authentication, and be
consumed once. The latest pending request must replace older requests.

The future integration must not return records in Siri dialogs, index them in
Spotlight, donate them to personal context, or make them transferable across
apps.
