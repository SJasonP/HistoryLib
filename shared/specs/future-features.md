# Future Feature Candidates

Status: candidate behavior for a post-1.4 release; only the explicitly noted
single-record menu actions are already present in Apple v1.4.

These candidates are recorded so that future implementations share the same
product meaning across native clients. They do not expand the current Apple
1.4 release claim.

## Export

### CSV

- Export one stored history record per CSV row.
- Include a header and the shared record fields needed for lossless round-trip
  analysis: URL, title, visit time, visit count, browser, source file, raw
  source timestamp, redirect metadata, HTTP GET metadata, and import time.
- Write UTF-8 CSV with standard quoting for commas, quotes, and line breaks.
- CSV is an analysis and portability format. It is not a synchronization or
  backup format.

## Domain deletion

- Provide a batch action for a selected hostname.
- Match the exact normalized hostname by default.
- Offer a separate explicit option to include subdomains; never include them
  implicitly.
- Show the affected count and require a destructive confirmation before saving
  the deletion.
- If a date is selected from the Library, interpret “that day” using the
  device's current calendar and time zone, with the end boundary exclusive.

## Record actions

Long-press or context-menu actions on a specific record may later expand to
include:

- **Open in Internet Archive**: open the current full URL through the
  archive.org Wayback service. The URL, including its query when present, is
  sent to that third-party service only after the user chooses the action.
- **Delete record**: already available in Apple v1.4 when deletion is enabled in
  Settings; future clients should match its authorization semantics.
- **Delete this site's records for the day**: delete records with the exact
  normalized hostname on the record's local calendar day, after showing the
  affected count and confirmation.

These actions must use the same deletion authorization, local-day boundaries,
hostname normalization, and sync behavior as the existing deletion controls.

## Time-based review

### This day in history

- Show records from the same local calendar month and day in earlier years.
- Use the device's current calendar and time zone for the comparison.
- Do not expose records from the current day twice in the same view.

### Annual review

- Review one natural calendar year at a time, using the device's current
  calendar and time zone.
- Distinguish saved-record counts from visit totals as defined in `summary.md`.
  Site and browser rankings must state which measure they use.
- The initial candidate may include total records, active days, top sites,
  browser distribution, and comparison with the previous calendar year.
- The review is derived presentation data; it must not add a new synchronized
  history entity unless a later design requires persistence.

## Open implementation questions

- Define the final CSV column names and whether a CSV import path is also
  required.
- Define the annual-review comparison metrics and empty-state behavior.
- Provide equivalent native context menus on Apple, Windows, and Android while
  preserving the same destructive-confirmation semantics.
