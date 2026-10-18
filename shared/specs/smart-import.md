# Smart Import Contract

Status: current cross-platform behavior

## Product surface

HistoryLib exposes one Import product action. Users choose an input location,
not an import format. The app detects Safari, Chrome Takeout, or HistoryLib
content automatically. An unrecognized input is rejected rather than guessed.

A platform may need a secondary native choice between selecting a file and
selecting a folder. This is an input-location choice and must not become a
Safari/Chrome/HistoryLib format picker.

## Supported sources

- Safari history export JSON files, directories, and ZIP containers.
- Google Takeout Chrome history JSON files, directories, and ZIP containers.
- HistoryLib `.hlz` archives, including password-protected HLZENC v1 archives.
- An unencrypted `.hlz` may also be presented through a generic ZIP or data
  content type; its identity comes from its contents.

## Detection order

1. Detect an HLZENC header or a HistoryLib manifest and archive structure.
2. Probe Safari content.
3. Probe Chrome Takeout content.
4. Reject the input.

Safari is probed before Chrome because both exports can use `History.json` as a
file name. File names and extensions are hints for system pickers only and are
not sufficient evidence of a format.

## Failure and mutation rules

- An input that cannot be identified must fail before any history insert.
- Unknown JSON and unknown ZIP inputs must leave the database unchanged.
- A HistoryLib archive must pass its complete structural, count, and checksum
  validation before any record is imported.
- Authentication of a password-protected archive must complete before its
  plaintext archive is trusted.
- A recognized multi-file directory can report invalid candidate files while
  importing valid files, matching the platform-neutral import report fields.
- Cancellation and partial-commit behavior must be visible in the result and
  must not claim an all-or-nothing outcome when batches were already committed.

## Import report

Every platform exposes equivalent result information:

- resolved format;
- scanned file count;
- valid file count;
- imported record count;
- skipped or merged record count;
- per-file failures;
- cancellation or terminal failure.

Progress supports both determinate and indeterminate phases. Parsing, hashing,
decryption, and database work must not block the UI thread.

## Resource and privacy rules

- Large Chrome Takeout arrays and HistoryLib JSONL chunks are streamed.
- Temporary files stay inside platform-private storage.
- ZIP paths are validated before extraction.
- Success, failure, and cancellation all clean temporary plaintext.
- Logs must not contain full URLs, page titles, passwords, or record payloads.
