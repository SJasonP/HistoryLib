import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct VersionRecoveryView: View {
    let currentBuild: Int
    let storedBuild: Int

    @State private var isClearing = false
    @State private var errorMessage: String?
    @State private var showingClearConfirmation = false
    @State private var showingClearSuccess = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This app build is older than the build that last opened your data.")
                    Text("Update HistoryLib, or stop iCloud sync and reset this device to use a separate local library.")
                        .foregroundStyle(.secondary)
                }

                Section("Build") {
                    LabeledContent("Current Build", value: String(currentBuild))
                    LabeledContent("Required Build", value: String(storedBuild))
                }

                Section {
                    Button("Stop Sync and Reset This Device", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .disabled(isClearing)

                    Button("Exit App") {
                        exitApp()
                    }
                    .disabled(isClearing)
                }

            }
            .navigationTitle("Update Required")
            .alert("Clear Data Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Confirm Clear All Data", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All Data", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("After restarting, this device's HistoryLib storage, settings, summaries, and caches will be reset. HistoryLib will use a separate local library with iCloud sync disabled. iCloud history and other devices will not be changed.")
            }
            .alert("Restart Required", isPresented: $showingClearSuccess) {
                Button("OK") {
                    exitApp()
                }
            } message: {
                Text("Restart HistoryLib to finish resetting this device in local-only mode. iCloud and other devices will not be changed.")
            }
            .overlay {
                if isClearing {
                    ZStack {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())

                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Clearing HistoryLib data…")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .floatingFeedbackSurface()
                    }
                    .onTapGesture { }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func clearAllData() {
        guard !isClearing else { return }
        isClearing = true
        Task { @MainActor in
                // The cloud store may already be open when KVS delivers a newer
                // build. Remove its files only at the next launch, before opening
                // any container. Never delete records through a live model context.
                AppSettingsCloudSync.shared.stopIfNeeded()
                let defaults = UserDefaults.standard
                for key in defaults.dictionaryRepresentation().keys where key != AppVersionGate.storedBuildKey {
                    defaults.removeObject(forKey: key)
                }
                DirectoryCountCache.clear()
                await ClearCacheStorageUsageCalculator.clearCacheDirectories()
                AppVersionGate.markCurrentBuild(currentBuild)
                defaults.set(true, forKey: AppVersionGate.localOnlyKey)
                defaults.set(true, forKey: AppVersionGate.pendingResetKey)
                defaults.set(storedBuild, forKey: AppVersionGate.requiredCloudBuildKey)
                isClearing = false
                showingClearSuccess = true
        }
    }

    private func exitApp() {
        UserDefaults.standard.synchronize()
#if os(macOS)
        NSApplication.shared.terminate(nil)
#else
        exit(0)
#endif
    }
}
