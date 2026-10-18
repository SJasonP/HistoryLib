# Summary Contract

Status: current 1.3 semantics retained for 1.4 parity

HistoryLib persists the latest generated summary snapshot and displays:

- total records;
- average records per day;
- average records per month;
- average records per year;
- top ten sites;
- snapshot generation time.

## Counting semantics

- `totalRecords` is the number of stored history records, not the sum of their
  `visitCount` values.
- Top-site counts add one for each stored record assigned to a host, not the
  record's `visitCount`.
- A valid URL host is trimmed and lowercased.
- A URL without a usable host is grouped under `(unknown)`.
- Top sites sort by count descending, then host ascending for ties, and retain
  the first ten.

The labels may suggest visits, but implementations must not silently change the
calculation on one platform. A future move to `visitCount`-weighted statistics
requires a coordinated product change, migration decision, UI-copy update, and
shared fixture update.

## Time spans

- Day span is inclusive from the calendar start of the earliest visit day to
  the calendar start of the latest visit day.
- Month span is inclusive by calendar year and month.
- Year span is inclusive by calendar year.
- Average is `totalRecords / inclusiveSpan`.
- An empty data set produces zero averages and no top-site entries.
- Displayed averages use two fractional digits.

## Regeneration

Summary generation is derived and cancellable. Imports, deletions, and relevant
sync changes schedule a coalesced refresh. Only the newest completed generation
may replace the persisted snapshot.
