import Foundation

@MainActor
final class AppSettingsCloudSync {
    static let shared = AppSettingsCloudSync()
    private let iCloudToggleKey = "enable_icloud_sync"

    private enum ValueKind {
        case bool
        case string
    }

    private struct SyncedSetting {
        let key: String
        let kind: ValueKind
    }

    private let settings: [SyncedSetting] = [
        .init(key: "show_history_time", kind: .bool),
        .init(key: "show_site_icons", kind: .bool),
        .init(key: "enable_delete", kind: .bool),
        .init(key: "open_record_in_browser_on_click", kind: .bool),
        .init(key: "default_expand_level", kind: .string),
        .init(key: "show_direct_search_results_on_iphone", kind: .bool)
    ]

    private let defaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default

    private var didStart = false
    private var lastSnapshot: [String: String] = [:]

    private init() {}

    func refreshActivationState() {
        if isICloudSyncEnabled {
            startIfNeeded()
        } else {
            stopIfNeeded()
        }
    }

    func startIfNeeded() {
        guard isICloudSyncEnabled else { return }
        guard !didStart else { return }
        didStart = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: defaults
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )

        _ = cloudStore.synchronize()

        // Prefer existing cloud values on startup so settings are restored across devices.
        pullAllFromCloudAndApplyToDefaults()

        // Push current local snapshot to cloud for keys that are local-only.
        lastSnapshot = makeSnapshot()
        pushSnapshotToCloud(lastSnapshot)
    }

    func stopIfNeeded() {
        guard didStart else { return }
        NotificationCenter.default.removeObserver(self)
        didStart = false
        lastSnapshot = [:]
    }

    private var isICloudSyncEnabled: Bool {
        defaults.object(forKey: iCloudToggleKey) as? Bool ?? true
    }

    @objc private func handleDefaultsDidChange() {
        let currentSnapshot = makeSnapshot()
        guard currentSnapshot != lastSnapshot else { return }

        for setting in settings {
            let key = setting.key
            let oldValue = lastSnapshot[key]
            let newValue = currentSnapshot[key]
            guard oldValue != newValue else { continue }
            writeCloudValue(newValue, for: setting)
        }

        lastSnapshot = currentSnapshot
    }

    @objc private func handleCloudStoreDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]

        if let changedKeys, !changedKeys.isEmpty {
            pullFromCloud(keys: Set(changedKeys))
        } else {
            pullAllFromCloudAndApplyToDefaults()
        }

        lastSnapshot = makeSnapshot()
    }

    private func pullAllFromCloudAndApplyToDefaults() {
        let keys = Set(settings.map(\.key))
        pullFromCloud(keys: keys)
    }

    private func pullFromCloud(keys: Set<String>) {
        for setting in settings where keys.contains(setting.key) {
            switch setting.kind {
            case .bool:
                if cloudStore.object(forKey: setting.key) != nil {
                    defaults.set(cloudStore.bool(forKey: setting.key), forKey: setting.key)
                }
            case .string:
                if let value = cloudStore.string(forKey: setting.key) {
                    defaults.set(value, forKey: setting.key)
                }
            }
        }
    }

    private func pushSnapshotToCloud(_ snapshot: [String: String]) {
        for setting in settings {
            writeCloudValue(snapshot[setting.key], for: setting)
        }
        _ = cloudStore.synchronize()
    }

    private func writeCloudValue(_ snapshotValue: String?, for setting: SyncedSetting) {
        switch setting.kind {
        case .bool:
            guard let snapshotValue else { return }
            cloudStore.set(snapshotValue == "1", forKey: setting.key)
        case .string:
            guard let snapshotValue else { return }
            cloudStore.set(snapshotValue, forKey: setting.key)
        }
    }

    private func makeSnapshot() -> [String: String] {
        var snapshot: [String: String] = [:]
        snapshot.reserveCapacity(settings.count)

        for setting in settings {
            switch setting.kind {
            case .bool:
                if defaults.object(forKey: setting.key) != nil {
                    snapshot[setting.key] = defaults.bool(forKey: setting.key) ? "1" : "0"
                }
            case .string:
                if let value = defaults.string(forKey: setting.key) {
                    snapshot[setting.key] = value
                }
            }
        }

        return snapshot
    }
}
