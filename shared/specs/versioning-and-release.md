# Versioning and Release Contract

HistoryLib is one product with native Apple, Android, and Windows clients in one
Git repository.

## Product version

- The repository root `VERSION` file is the intended public product version.
- User-visible platform versions must match `VERSION` for a coordinated
  release.
- Platform build identifiers may differ because app stores use different
  schemes: Apple build number, Android `versionCode`, and Windows revision.
- A platform-specific build identifier does not create a different product
  feature version.

## History and 1.4 transition

- Tags `v1.0` through `v1.3` describe the historical Apple-only repository.
- HistoryLib 1.4 is planned as the first coordinated Apple, Android, and Windows
  release.
- Existing historical tags must not be moved or rewritten.
- The coordinated `v1.4` tag is created only from a commit that satisfies the
  shared parity and interoperability gates for all three platforms.

## Release gate

A coordinated release requires:

- required parity features complete on all platforms;
- shared import, deduplication, archive, privacy, and localization contracts
  satisfied;
- platform unit, integration, UI, static-analysis, and release builds passing;
- cross-platform `.hlz` fixtures passing in both directions;
- release notes based on the requested base tag through the release commit;
- platform store metadata showing the same public product version.
