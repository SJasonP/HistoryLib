import SwiftUI
import SwiftData

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum AppVersionGateStatus {
    case normal(currentBuild: Int)
    case requiresRecovery(currentBuild: Int, storedBuild: Int)
}

enum AppVersionGate {
    static let storedBuildKey = "historylib.lastKnownBuildVersion"
    static let localOnlyKey = "historylib.recovery.localOnly"
    static let requiredCloudBuildKey = "historylib.recovery.requiredCloudBuild"
    static let pendingResetKey = "historylib.recovery.pendingReset"
    static let pendingResumeKey = "historylib.recovery.pendingResume"

    static var usesLocalOnlyStorage: Bool { UserDefaults.standard.bool(forKey: localOnlyKey) }

    static func storeURL(localOnly: Bool) -> URL {
        let schema = Schema([Item.self, SummarySnapshot.self])
        let defaultURL = ModelConfiguration(schema: schema, cloudKitDatabase: .none).url
        return localOnly ? defaultURL.deletingLastPathComponent().appendingPathComponent("HistoryLib-local-only.store") : defaultURL
    }

    static var currentBuild: Int {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return 0
        }
        return Int(raw) ?? 0
    }

    static func evaluate(defaults: UserDefaults = .standard, currentBuild: Int = Self.currentBuild, cloudBuild: Int = 0) -> AppVersionGateStatus {
        let storedBuild = defaults.integer(forKey: storedBuildKey)
        let detectedBuild = currentBuild
        let requiredBuild = defaults.bool(forKey: localOnlyKey) ? storedBuild : max(storedBuild, cloudBuild)
        guard detectedBuild >= requiredBuild else {
            return .requiresRecovery(currentBuild: detectedBuild, storedBuild: requiredBuild)
        }
        defaults.set(detectedBuild, forKey: storedBuildKey)
        return .normal(currentBuild: detectedBuild)
    }

    static func markCurrentBuild(_ build: Int = currentBuild, defaults: UserDefaults = .standard) {
        defaults.set(build, forKey: storedBuildKey)
    }
}

@main
struct HistoryLibApp: App {
    @State private var versionGateStatus: AppVersionGateStatus
    @State private var cloudBuildVersion = CloudBuildVersion.shared
    let sharedModelContainer: ModelContainer
    let runsLocalOnly: Bool
    let resetError: String?

    init() {
        let defaults = UserDefaults.standard
        var resetError: String?
        if defaults.bool(forKey: AppVersionGate.pendingResumeKey) {
            defaults.removeObject(forKey: AppVersionGate.localOnlyKey)
            defaults.removeObject(forKey: AppVersionGate.pendingResumeKey)
        }
        if defaults.bool(forKey: AppVersionGate.pendingResetKey) {
            do {
                try LocalStoreReset.removeStore(at: AppVersionGate.storeURL(localOnly: false))
                try LocalStoreReset.removeStore(at: AppVersionGate.storeURL(localOnly: true))
                AppVersionGate.markCurrentBuild()
                defaults.removeObject(forKey: AppVersionGate.pendingResetKey)
            } catch {
                resetError = error.localizedDescription
            }
        }
        self.resetError = resetError
        runsLocalOnly = AppVersionGate.usesLocalOnlyStorage
#if DEBUG
        if !UITestStore.isUnitTesting { CloudBuildVersion.shared.start() }
#else
        CloudBuildVersion.shared.start()
#endif
        let status = AppVersionGate.evaluate(cloudBuild: CloudBuildVersion.shared.highestBuild)
        _versionGateStatus = State(initialValue: status)
        sharedModelContainer = Self.makeModelContainer(status: status, resetFailed: resetError != nil)
    }

    private static func makeModelContainer(status: AppVersionGateStatus, resetFailed: Bool) -> ModelContainer {
        let schema = Schema([
            Item.self,
            SummarySnapshot.self,
        ])
#if DEBUG
        if UITestStore.isUnitTesting {
            return UITestStore.makeContainer(schema: schema, seedRecords: false)
        }
        if ProcessInfo.processInfo.environment["HISTORYLIB_UI_TESTING"] == "1" {
            return UITestStore.makeContainer(schema: schema)
        }
#endif
        // Never open or migrate a newer on-disk store, or start CloudKit, on downgrade.
        if case .requiresRecovery = status {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [configuration])
        }
        if resetFailed {
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        }
        let defaults = UserDefaults.standard
        if AppVersionGate.usesLocalOnlyStorage {
            let configuration = ModelConfiguration(schema: schema, url: AppVersionGate.storeURL(localOnly: true), cloudKitDatabase: .none)
            do {
                let container = try ModelContainer(for: schema, configurations: [configuration])
                defaults.set("localOnly", forKey: "persistence_backend")
                defaults.removeObject(forKey: "persistence_error")
                return container
            } catch {
                defaults.set("memoryFallback", forKey: "persistence_backend")
                defaults.set(error.localizedDescription, forKey: "persistence_error")
                return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
            }
        }
        // Sync consent is controlled by system iCloud settings from v1.4.
        defaults.removeObject(forKey: "enable_icloud_sync")
        defaults.removeObject(forKey: "persistence_launch_icloud_enabled")
        HistorySyncActivity.shared.startObserving()

        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            HistorySyncActivity.shared.bind(to: container)
            CloudBuildVersion.shared.publishCurrentBuild()
            defaults.set("primary", forKey: "persistence_backend")
            defaults.removeObject(forKey: "persistence_error")
            print("Persistence backend: Primary store (automatic CloudKit integration)")
            return container
        } catch {
            // Recovery permits reading/exporting only; never silently accept
            // mutations after the primary container fails to open.
            let cloudError = String(describing: error)
            print("CloudKit ModelContainer init failed: \(cloudError)")
            let localConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            do {
                let container = try ModelContainer(for: schema, configurations: [localConfiguration])
                defaults.set("localFallback", forKey: "persistence_backend")
                defaults.set(cloudError, forKey: "persistence_error")
                print("Persistence backend: Local fallback")
                return container
            } catch {
                // Final fallback for schema migration/debug issues.
                let localError = String(describing: error)
                print("Local ModelContainer init failed: \(localError)")
                let memoryOnlyConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                do {
                    let container = try ModelContainer(for: schema, configurations: [memoryOnlyConfiguration])
                    defaults.set("memoryFallback", forKey: "persistence_backend")
                    defaults.set("Cloud error: \(cloudError)\nLocal error: \(localError)", forKey: "persistence_error")
                    print("Persistence backend: In-memory fallback")
                    return container
                } catch {
                    fatalError("Could not create ModelContainer: \(error)")
                }
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if let resetError {
            ContentUnavailableView("Clear Data Failed", systemImage: "exclamationmark.triangle", description: Text(resetError))
        } else {
#if DEBUG
        if UITestStore.isUnitTesting {
            Color.clear
        } else if case let .requiresRecovery(currentBuild, storedBuild) = effectiveVersionGateStatus {
            versionRecoveryView(currentBuild: currentBuild, storedBuild: storedBuild)
        } else {
            applicationContent
        }
#else
        if case let .requiresRecovery(currentBuild, storedBuild) = effectiveVersionGateStatus {
            versionRecoveryView(currentBuild: currentBuild, storedBuild: storedBuild)
        } else {
            applicationContent
        }
#endif
        }
    }

    private var effectiveVersionGateStatus: AppVersionGateStatus {
        if case .requiresRecovery = versionGateStatus { return versionGateStatus }
        let cloudBuild = cloudBuildVersion.highestBuild
        if !runsLocalOnly, cloudBuild > AppVersionGate.currentBuild {
            return .requiresRecovery(currentBuild: AppVersionGate.currentBuild, storedBuild: cloudBuild)
        }
        return versionGateStatus
    }

    private func versionRecoveryView(currentBuild: Int, storedBuild: Int) -> some View {
        VersionRecoveryView(currentBuild: currentBuild, storedBuild: storedBuild)
    }

    @ViewBuilder
    private var applicationContent: some View {
#if os(macOS)
        MacPrivacyLockGate {
            ContentView()
        }
        .task { AppSettingsCloudSync.shared.refreshActivationState() }
#else
        ContentView()
            .task { AppSettingsCloudSync.shared.refreshActivationState() }
#endif
    }

    var body: some Scene {
        WindowGroup {
            rootContent

        }
        .modelContainer(sharedModelContainer)

#if os(macOS)
        Settings {
            if case .normal = effectiveVersionGateStatus, resetError == nil {
                AppSettingsView()
            } else {
                Text("Update Required")
            }
        }
#endif
    }
}
