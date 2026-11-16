import SwiftUI
#if os(macOS)
import AppKit
#endif

struct LocalOnlyRecoverySection: View {
    @State private var showingResume = false

    var body: some View {
        Section("iCloud") {
            Text("Local Only")
            Text("Update HistoryLib before resuming iCloud sync.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Resume iCloud Sync") { showingResume = true }
                .disabled(AppVersionGate.currentBuild < UserDefaults.standard.integer(forKey: AppVersionGate.requiredCloudBuildKey))
        }
        .alert("Resume iCloud Sync", isPresented: $showingResume) {
            Button("Cancel", role: .cancel) { }
            Button("OK") {
                UserDefaults.standard.set(true, forKey: AppVersionGate.pendingResumeKey)
                UserDefaults.standard.synchronize()
#if os(macOS)
                NSApplication.shared.terminate(nil)
#else
                exit(0)
#endif
            }
        } message: {
            Text("Restart to resume iCloud sync. The separate local library will be kept; export its records first if you want to import them into iCloud.")
        }
    }
}
