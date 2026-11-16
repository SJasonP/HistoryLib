import Foundation
import Observation

/// Advisory compatibility markers. KVS is eventually consistent, not a lock
/// capable of stopping offline clients or versions shipped without this gate.
@MainActor
@Observable
final class CloudBuildVersion {
    static let shared = CloudBuildVersion()
    static let prefix = "historylib.compatibility.build."
    private(set) var highestBuild = 0
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let store = NSUbiquitousKeyValueStore.default

    func start() {
        guard observer == nil, !UserDefaults.standard.bool(forKey: AppVersionGate.localOnlyKey) else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.readMarkers() }
        }
        _ = store.synchronize()
        readMarkers()
    }

    func publishCurrentBuild() {
        guard !UserDefaults.standard.bool(forKey: AppVersionGate.localOnlyKey) else { return }
        // Independent immutable build keys avoid an offline older client
        // overwriting a newer build's high-water mark with last-writer-wins.
        store.set(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                  forKey: Self.prefix + String(AppVersionGate.currentBuild))
        readMarkers()
        let builds = Self.builds(in: store.dictionaryRepresentation).sorted(by: >)
        for build in builds.dropFirst(64) {
            store.removeObject(forKey: Self.prefix + String(build))
        }
        _ = store.synchronize()
    }

    private func readMarkers() {
        highestBuild = Self.builds(in: store.dictionaryRepresentation).max() ?? 0
        if highestBuild > AppVersionGate.currentBuild {
            AppSettingsCloudSync.shared.stopIfNeeded()
        }
    }

    static func builds(in values: [String: Any]) -> [Int] {
        values.keys.compactMap { key in
            guard key.hasPrefix(prefix), let build = Int(key.dropFirst(prefix.count)), build > 0 else { return nil }
            return build
        }
    }
}
