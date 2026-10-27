# Deduplication Contract

Status: current cross-platform behavior

All importers and post-sync duplicate cleaners use the same normalization and
matching implementation on each platform. Format-specific importers must not
maintain independent variants of these rules.

## Canonical entry

Given a raw URL, visit time, and browser name:

1. Trim leading and trailing whitespace from the URL.
2. Parse the URL when possible.
3. Lowercase the scheme and host.
4. Remove the fragment.
5. Remove port 80 from HTTP and port 443 from HTTPS.
6. Replace an empty path with `/`.
7. Remove a trailing slash from a non-root path.
8. If parsing fails, use the trimmed URL lowercased.
9. Trim and lowercase the browser name.
10. Floor the visit time to a Unix second.

The canonical signature is:

```text
normalizedURL|visitedSecond|normalizedBrowser
```

## Matching

- Exact signature matching is always enabled.
- Near-duplicate matching is enabled by default with a tolerance of one second.
- With tolerance `n`, the matcher checks every signature from
  `visitedSecond - n` through `visitedSecond + n`, inclusive.
- Matching applies both against records already stored and records accepted in
  the current batch.

## Merge result

- A duplicate does not create another stored record.
- Its `visitCount`, clamped to at least one before merge, is added to the
  existing record's count.
- If the sum exceeds the platform's count storage range, it saturates at that
  range's maximum; it must never wrap or terminate the process. The same rule
  applies to imported, already-persisted, and synced records, including every
  intermediate accumulator in post-sync cleanup. An empty accumulator is zero.
- The operation is reported as skipped or merged rather than imported.
- Rich optional metadata must not be replaced by poorer empty metadata. Exact
  precedence rules must be covered by shared fixtures before implementations
  add new merge behavior.

## Persistence requirements

- Visit time and `uniqueKey` require database indexes.
- A database unique constraint is not a replacement for semantic merge logic.
- Timestamp storage must preserve UTC Unix microseconds even though matching
  operates at whole-second precision.
