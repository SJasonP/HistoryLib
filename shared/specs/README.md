# Shared Specifications

This directory is the platform-neutral source of truth for HistoryLib behavior.
It specifies observable product semantics, file formats, compatibility rules,
and privacy requirements. It does not require platforms to share runtime code.

Each released client implements and tests the contracts in its release scope.
Apple v1.4 is the current release scope; Android and Windows remain under
development. Platform-native layout and interaction may differ when behavior
remains equivalent. Apple-specific additions are identified in each contract.

## Specifications

- [`search.md`](search.md): structured search and optional Apple intelligence integration.
- [`product-parity.md`](product-parity.md): required shared feature surface.
- [`history-record.md`](history-record.md): logical persistent record and time semantics.
- [`browser-history-formats.md`](browser-history-formats.md): Safari and Chrome JSON contracts.
- [`smart-import.md`](smart-import.md): content detection, rejection, and import reporting.
- [`deduplication.md`](deduplication.md): URL normalization, matching, and merge behavior.
- [`hlz-v1.md`](hlz-v1.md): canonical HistoryLib archive and encryption format.
- [`summary.md`](summary.md): aggregate counting and snapshot semantics.
- [`sync.md`](sync.md): platform-local sync, availability, and local-only recovery.
- [`privacy-and-data.md`](privacy-and-data.md): sensitive-data, export, cache, and logging rules.
- [`localization.md`](localization.md): common language completeness requirements.
- [`tips-and-support.md`](tips-and-support.md): voluntary Apple developer-support tips and App Store Connect requirements.
- [`versioning-and-release.md`](versioning-and-release.md): unified product version and release gates.
- [`future-features.md`](future-features.md): post-1.4 candidate features and
  their settled semantics.
