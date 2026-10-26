import SwiftUI
import SwiftData

@main
struct HistoryLibApp: App {
    var sharedModelContainer: ModelContainer = {
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
        let defaults = UserDefaults.standard
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
    }()

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if UITestStore.isUnitTesting {
            Color.clear
        } else {
            applicationContent
        }
#else
        applicationContent
#endif
    }

    private var applicationContent: some View {
        ContentView()
            .task { AppSettingsCloudSync.shared.refreshActivationState() }
    }

    var body: some Scene {
        WindowGroup {
            rootContent
        }
        .modelContainer(sharedModelContainer)

#if os(macOS)
        Settings {
            AppSettingsView()
        }
#endif
    }
}
