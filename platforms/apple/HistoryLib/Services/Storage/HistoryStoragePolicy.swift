/// History must never appear durably saved when only the recovery store exists.
/// Sync-mode changes also remain read-only until the next launch.
enum HistoryStoragePolicy {
    static func canMutate(backend: String, syncEnabled: Bool, launchSyncEnabled: Bool) -> Bool {
        guard backend != "memoryFallback", syncEnabled == launchSyncEnabled else { return false }
        return !syncEnabled || backend == "cloudKit"
    }
}
