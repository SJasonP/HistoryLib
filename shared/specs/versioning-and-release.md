# Versioning and Release Contract

HistoryLib is one product with native clients in one Git repository. The root
`VERSION` is the intended public feature version. Platform build identifiers
may differ; they do not define separate feature versions.

## Current release scope

On October 26, 2026, the release scope was changed to **Apple only** for v1.4:
iOS and macOS. Android and Windows releases are deferred. Their source and
shared format contracts remain available for future work, but their builds,
parity status, and bidirectional interoperability are not blockers for this
Apple-only release and must not be advertised as released capabilities.

A later Android/Windows release must explicitly define its version and scope,
and pass its own implementation and compatibility gates before shipping.
Future coordinated releases require parity and interoperability for every
platform included in that release; do not imply that an Apple release proves
another platform compatible.

## Apple v1.4 gates

Build rollback protection checks both the device's last-opened build and the
highest known build from iCloud key-value storage before opening persistence.
Independent per-build KVS markers prevent an older offline client overwriting
a newer marker. Retain the newest 64 markers to bound key usage. Observe later
KVS updates and block the UI when a newer cloud build arrives.

Offer upgrading, exiting, or explicit local-only recovery. Recovery requires
confirmation, disables settings sync, and stages a local reset for next launch;
never unlink a live store or submit record deletions to CloudKit. After restart,
remove the old local store and sidecars before opening any container, then use
a separate local-only database with CloudKit disabled. Other devices and cloud
records are retained. Resuming cloud sync requires at least the recorded build,
explicit confirmation, and restart; retain the local-only library and explain
that its records must be exported/imported if wanted in the cloud library.

KVS is eventually consistent: this does not guarantee a cloud version check
before every sync, cannot protect offline clients, and cannot retrofit a gate
into already-shipped older binaries. Schema changes must remain additive and
compatible with those clients; version markers are an additional precaution.
Summary loading and pruning are scoped to the generating build so a different
client build's derived statistics are neither displayed nor removed by v1.4.

- The Apple app marketing version matches `VERSION`; the build number is
  greater than previously distributed Apple builds.
- Required Apple behavior, six-language resources, `.hlz` compatibility,
  read-only recovery behavior, and privacy declarations are verified.
- Apple unit/integration tests, static checks, iOS/macOS Release builds, and
  final artifact metadata checks pass. Human interactive acceptance is recorded
  separately from automated test results.
- The security audit is completed against the final source revision and pinned
  dependencies; required fixes are applied and revalidated.
- Humans verify interactive upgrades, CloudKit sync, visual behavior, and that
  the disabled Apple Intelligence/Siri integrations remain absent while manual
  keyword search and advanced filters work as documented.
- macOS verifies the default privacy lock, successful and cancelled native
  authentication, the Settings opt-out, and relaunch behavior. Windows keeps
  the same contract for its deferred release; Android documents the device
  privacy-lock boundary.
- Before distribution, verify the CloudKit production schema and entitlements,
  signed archives, store metadata/privacy answers, and export-compliance answers.
- Release notes describe the changes since v1.3 and identify the Apple-only
  scope. A prepared changelog entry is not proof of publication.

## Tags and publication

Historical tags `v1.0` through `v1.3` remain unchanged. Create `v1.4` only after
its Apple gates are satisfied and publication is explicitly authorized. Never
create or move a release tag merely to mark an audit candidate. Release notes
belong in the existing `CHANGELOG.md`. Keep temporary verification and audit
preparation records outside the repository.
