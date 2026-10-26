# Sync Contract

Status: decided for HistoryLib 1.4

Sync and backup are distinct. HistoryLib has no product-level backup feature;
sync maintains an active data set across devices that support it and must
define conflict and availability behavior.

## Product decision

HistoryLib 1.4 uses **platform-local sync**. Each platform syncs only within
its own platform ecosystem:

- Apple: iCloud (CloudKit), controlled by system iCloud settings in Apple 1.4.
- Android: an Android-native sync provider, if implemented.
- Windows: a Windows-native sync provider, if implemented.

There is no cross-platform shared data set in 1.4. A neutral cross-platform
sync service is explicitly out of scope for this release.

## Platform opt-out

If platform-local sync is technically impractical for a specific platform,
that platform may ship without sync. Opting out is a documented platform
limitation, not a silent omission:

- The platform must expose an explicit "sync unsupported" state instead of a
  broken or partial sync experience.
- The platform's store copy, settings, and Help must state that sync is not
  available on that platform.
- The platform must not claim parity for sync, and must not present backup or
  local-only storage as a substitute.
- The limitation must be recorded in the platform documentation or in
  `product-parity.md` before release.

Where a platform ships sync, it must meet the requirements below; where a
platform documents that it does not ship sync, that is an accepted platform
limitation and is not a parity violation.

## Required semantics for platforms that ship sync

Every platform that ships sync must expose equivalent meaning for:

- sync disabled and local-only storage;
- sync enabled;
- activation state;
- an accessible status surface, updated automatically or by an explicit action;
- unavailable/error state;
- protection against silently accepting writes into a recovery store;
- duplicate cleanup after remote changes;
- settings that participate in sync.

Platform-native service names and authorization UI may differ, but the product
must not present a backup mechanism as sync.

### Apple 1.4 system control

System iCloud settings are the sole sync control. The app-specific switch and
its saved preference are removed; the existing store is retained. Release notes
must explain that the old app-level opt-out no longer applies.

An opened primary store remains writable regardless of connectivity, account
availability, cloud quota, or observed sync errors. CloudKit scheduling and
retry behavior belong to the system; local saves do not promise remote delivery.
If the primary container cannot open, persistent and in-memory recovery modes
remain read-only for history. Do not silently redirect mutations to recovery.
System account/access changes can affect mirrored local data; this policy does
not guarantee that disabling iCloud preserves a separate local library.

Manage displays account availability and local/cloud history counts when
readable. Account availability does not prove that the system's per-app switch
is enabled or synchronization has completed. Incomplete/failed counts display
unavailable rather than partial counts or a false zero. Diagnostics update only
while the page is visible and active.

Manage also shows observed upload/download activity and the latest successful
transfer time in the current app session. Passive sync-event capture continues
outside Manage without starting polling or network requests. Setup success is
not a successful transfer, and no active event is not proof of completed sync.

Change iCloud Settings shows an explanation of Apple's control and navigation
directions, with only an OK action; OK opens system settings through the
platform-supported entry point. Do not promise a direct iCloud subpage link.

## Prohibited shortcuts

- Android Auto Backup is not sync.
- Periodically copying a live SwiftData, Room, or SQLite database file is not
  record synchronization.
- A client must not claim that a successful local save proves remote delivery,
  or silently accept mutations into a recovery store after primary-store failure.
- A platform that ships without sync must not present local-only storage as
  sync, and a platform that ships sync must not present it as backup.

## Cross-platform sync

Cross-platform sync is not selected for 1.4. If it is reconsidered in a later
release, a neutral design requires shared definitions for stable record
identity, incremental cursors, deletion tombstones, conflict resolution,
visit-count merge behavior, offline queues, authentication, encryption, key
recovery, schema migration, and account deletion. These rules must be written
into the shared specifications before implementation begins.
