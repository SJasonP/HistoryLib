# Summary Contract

This document describes the Apple v1.4 summary. Deferred Android and Windows
clients may retain the earlier record-count summary until their next release;
they must not label those counts as visit totals.

## Displayed metrics

- Saved records: the number of stored history entries.
- Active days: distinct local calendar days containing at least one record.
- Total visits: the sum of `max(visitCount, 1)` across stored records.
- Average per active day: saved records divided by active days.
- Date coverage: earliest through latest visit date.
- Average records per calendar month and year across that coverage.
- Monthly activity, browser distribution, and the top ten sites by visits.
- Snapshot generation time.

Saved records and visits are different measures. Importing merged records can
produce a visit total greater than the number of saved records; the UI explains
this distinction. These statistics describe imported data, not additional
visits observed by HistoryLib.

## Sites, browsers, and months

- Site, browser, and monthly totals use stored visit counts, clamped to at
  least one per record.
- Hosts are trimmed and lowercased. Unusable hosts are excluded from the site
  ranking; they still contribute to overall, browser, and monthly totals.
- Sites sort by visits descending, then host ascending for ties. Keep ten.
- Browser groups use the stored source-browser value, sorted by visits
  descending and then name ascending.
- Month buckets use the user's local calendar and `YYYY-MM` labels, sorted
  chronologically. The chart scrolls horizontally and initially shows the
  latest months. Axes scale to the displayed data.
- Selecting a known top site applies the corresponding domain search.

## Time spans

- Calendar day, month, and year spans include both the earliest and latest
  occupied periods, including intervening periods with no saved records.
- Coverage averages divide saved records by the inclusive span, while the
  active-day average divides by occupied days only.
- Empty data produces zero averages and no rankings.
- Displayed averages use two fractional digits.

## Regeneration and compatibility

Summary generation is derived and cancellable. Imports, deletions, and relevant
sync changes schedule a coalesced refresh. Only the newest completed generation
may update the UI and replace that build's persisted snapshots.

Snapshots record their generating app build. The Apple client loads and
replaces only snapshots for its own build, rebuilding when none exists or
stored counts are stale. Older snapshots without build metadata are treated
as stale. Directory-count caches also validate their generating build, total
record count, and time zone. Rebuilding derived data never changes history.
