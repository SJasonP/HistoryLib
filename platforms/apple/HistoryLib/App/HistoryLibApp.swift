import SwiftUI
import SwiftData

@main
struct HistoryLibApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            SummarySnapshot.self,
        ])
        let defaults = UserDefaults.standard
        let isICloudSyncEnabled = defaults.object(forKey: "enable_icloud_sync") as? Bool ?? false
      
        // Record the sync mode the store is actually being created with, so the UI
        // can detect when the saved setting has changed and a relaunch is required.
        defaults.set(isICloudSyncEnabled, forKey: "persistence_launch_icloud_enabled")

        if !isICloudSyncEnabled {
            let localConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            do {
                let container = try ModelContainer(for: schema, configurations: [localConfiguration])
                defaults.set("localUserDisabledICloud", forKey: "persistence_backend")
                defaults.removeObject(forKey: "persistence_error")
                print("Persistence backend: Local (iCloud disabled by user)")
                return container
            } catch {
                let localError = String(describing: error)
                print("Local ModelContainer init failed: \(localError)")
                let memoryOnlyConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    let container = try ModelContainer(for: schema, configurations: [memoryOnlyConfiguration])
                    defaults.set("memoryFallback", forKey: "persistence_backend")
                    defaults.set("Local error: \(localError)", forKey: "persistence_error")
                    print("Persistence backend: In-memory fallback")
                    return container
                } catch {
                    fatalError("Could not create ModelContainer: \(error)")
                }
            }
        }

        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [cloudConfiguration])
            defaults.set("cloudKit", forKey: "persistence_backend")
            defaults.removeObject(forKey: "persistence_error")
            print("Persistence backend: CloudKit")
            return container
        } catch {
            // Keep the app usable even if CloudKit capability/signing is not ready.
            let cloudError = String(describing: error)
            print("CloudKit ModelContainer init failed: \(cloudError)")
            let localConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
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
                let memoryOnlyConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    AppSettingsCloudSync.shared.refreshActivationState()
                }
        }
        .modelContainer(sharedModelContainer)

#if os(macOS)
        Settings {
            AppSettingsView()
        }
#endif
    }
}
