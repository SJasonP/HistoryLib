# Search and Optional Intelligence

Status: Apple enhancement; other clients retain their existing keyword search.
This is an optional Apple capability. Android and Windows are deferred from v1.4.

## Structured search

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

## Natural language

The first Apple implementation explicitly uses the on-device Foundation Models
system model. It receives only the user's request, the reference date/time zone,
and fixed parsing instructions. No history entries, URLs, titles, passwords,
archive content, database schema, or retrieval tools are supplied to the model.
There is no automatic cloud fallback.

Generated output is a proposed structured filter. Reject unsupported requests,
invalid dates/domains, unsupported browsers, and empty proposals. The user must
review and apply the editable proposal before it queries the history store.

Model availability and language support vary. Manual filters and keyword
search remain usable without Apple Intelligence. Interpretation failure must
not silently substitute a keyword search or clear a previously edited filter.

This feature does not infer webpage bodies, generate visit records, reconstruct
actual navigation links, or guarantee semantic recall from missing content.

## Siri and Shortcuts

Apple exposes foreground keyword search and a natural-language preparation
action. The latter opens the editor; it does not infer or execute automatically.
The system search schema routes to ordinary keyword search. Requests require
local device authentication, are bounded, and stay only in memory. The latest
pending request wins if multiple requests arrive before it can be handled.

Requests arriving before UI startup or during import/export/password/document
presentations remain pending until the interface can handle them. A consumed
request must not replay on a later appearance or tab switch.

No records are returned in Siri dialogs, indexed in Spotlight, donated to
personal context, or made transferable across apps by this implementation.
The user explicitly submits the query to Siri/Shortcuts; only the foreground
application reads its history database to display results. System capability
availability is independent from app compilation and requires separate human
end-to-end acceptance.
