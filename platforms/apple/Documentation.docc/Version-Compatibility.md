# Version Compatibility

Before persistence opens, compare the current build against the local last-opened
build and known iCloud KVS markers. Normal startup publishes an independent key
for the current build; older offline clients cannot overwrite higher keys. Keep
the newest 64 keys. Observe KVS changes while running and replace app content
with recovery if a higher build becomes known; disappearing content cancels
imports, exports, summary generation, directory work, and background dedup.

The recovery page offers instructions to update, Exit App, and Stop Sync and
Reset This Device. Confirming reset stops settings synchronization, clears local
preferences/caches, and persists a pending reset and required cloud build. It
then asks the user to restart. On next launch, remove the original local store,
SQLite sidecars, and external-data support directory before any persistent
container opens. Start a separate local-only database with no CloudKit. Never
delete cloud records or zones. Settings synchronization and cloud diagnostics
remain disabled in local-only mode.

After upgrading to at least the required build, Manage offers Resume iCloud Sync.
Confirmation schedules the switch for restart. The separate local library is
retained; the user can export its contents before switching and import them
into the cloud library. Nothing is silently merged or discarded.

KVS synchronization is eventual, not a distributed lock. A late version marker
cannot undo cloud operations already performed, and older shipped binaries
without this gate continue to run. Keep schema migrations additive and preserve
old-client interoperability. Never infer that networking errors or account
status mean the system per-app iCloud switch is off.

## Acceptance

- Same-device downgrade blocks before opening persistent storage.
- Cached higher KVS build blocks startup; a later notification blocks a running UI.
- Account changes refresh known markers; a lower marker never hides a higher one.
- Local-only reset leaves cloud history and another device's records intact.
- Restart opens the independent local store and permits local imports/deletes.
- Settings and cloud-count polling stay disabled in local-only mode.
- Upgrade enables explicit resume, retaining the local store for later export.
- Exercise offline and delayed KVS delivery; do not claim immediate enforcement.
