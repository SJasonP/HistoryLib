# History Record Contract

Status: current cross-platform schema

Every platform maps its native persistence model to the following logical
record. Native column and property names may differ only when the mapping is
lossless.

| Field | Type | Required | Meaning |
|---|---|---:|---|
| `uniqueKey` | string | yes | Canonical deduplication signature |
| `url` | string | yes | Original record URL |
| `title` | string | yes | Page title; empty when unavailable |
| `visitedAtUsec` | int64 | yes | Visit time as Unix microseconds in UTC |
| `visitCount` | integer | yes | Merged visit count, minimum 1 |
| `sourceBrowser` | string | yes | Source browser display name |
| `sourceFileName` | string | yes | Source file name; empty when unavailable |
| `rawTimeUsec` | int64 | yes | Original source timestamp; 0 when unavailable |
| `sourceURL` | string | no | Redirect source URL |
| `sourceTimeUsec` | int64 | no | Redirect source timestamp |
| `destinationURL` | string | no | Redirect destination URL |
| `destinationTimeUsec` | int64 | no | Redirect destination timestamp |
| `latestVisitWasHttpGet` | boolean | no | Latest-visit HTTP GET metadata |
| `importedAtUsec` | int64 | yes | Import time as Unix microseconds in UTC |

## Time rules

- Unix microseconds are the cross-platform source of truth.
- A platform may expose a native date/time object in memory but must preserve
  the microsecond value for import/export round trips.
- Keep original integer timestamps when the native date representation loses
  precision. Serializing an older native-only date must check finiteness and
  integer representability and return a controlled error for unsafe values.
- UI grouping and display use the user's current calendar, locale, and time
  zone. Persisted timestamps remain UTC.
- Deduplication floors visit time to a Unix second without discarding the
  stored microsecond value.

## Indexing

Native databases require indexes supporting visit-time ordering and
`uniqueKey` lookup. The key is not a substitute for the merge behavior in
`deduplication.md` and does not have to be a database unique constraint.

## Evolution

- New optional fields require updates to `.hlz`, persistence migrations, and
  cross-platform fixtures before adoption.
- Removing or changing the meaning of a field is a breaking product-data
  change.
- Unknown future `.hlz` record fields are ignored as required by `hlz-v1.md`.
