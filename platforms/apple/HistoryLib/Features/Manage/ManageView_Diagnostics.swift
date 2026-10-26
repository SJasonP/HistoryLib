import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension ManageView {
    var monitoringEnabled: Bool { isActive && isVisible && scenePhase == .active }

    var syncSection: some View {
        Section("iCloud") {
            LabeledContent("Sync Control", value: String(localized: "Managed by System"))
            LabeledContent("iCloud Account", value: diagnostics.accountMessage)
            LabeledContent("Local Records", value: countText(diagnostics.localCount))
            LabeledContent("Cloud Records", value: countText(diagnostics.cloudCount))
            Text(diagnostics.cloudMessage).font(.footnote).foregroundStyle(.secondary)
            Button("Change iCloud Settings") { showingICloudGuide = true }
        }
    }

    var cacheSection: some View {
        Section("Storage") {
            if let usage = diagnostics.storageUsage {
                LabeledContent("Clearable Cache", value: byteCount(usage.clearableCacheBytes))
                LabeledContent("Protected Data", value: byteCount(usage.nonClearableDataBytes))
                LabeledContent("Database", value: byteCount(usage.databaseBytes))
                LabeledContent("Database Journals", value: byteCount(usage.databaseJournalBytes))
            } else {
                Text("Calculating Cache Size...").foregroundStyle(.secondary)
            }
            Text("Clear Cache removes disposable files and releases loaded search results. It also asks the database to reclaim completed journals. History, indexes, sync metadata, and busy journals are preserved.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Site icons are turned off when clearing to prevent immediate downloads. Active transfers must finish first.")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                guard !diagnostics.isClearing else { return }
                diagnostics.isClearing = true
                showSiteIcons = false
                Task { @MainActor in
                    switch await onClearCache() {
                    case .completed:
                        diagnostics.cacheMessage = String(localized: "Cache clearing finished.")
                    case .busy:
                        diagnostics.cacheMessage = String(localized: "Cache cleared. Some database journals are busy; try again later.")
                    case .unavailable:
                        diagnostics.cacheMessage = String(localized: "Cache cleared. Database journal maintenance could not finish.")
                    }
                    if monitoringEnabled {
                        let usage = await onMeasureStorageUsage()
                        if monitoringEnabled { diagnostics.storageUsage = usage }
                    }
                    diagnostics.isClearing = false
                }
            } label: {
                if diagnostics.isClearing { ProgressView() } else { Text("Clear Cache") }
            }
            .disabled(diagnostics.isClearing || isImporting || isPreparingExport)
            if let message = diagnostics.cacheMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    func countText(_ count: Int?) -> String {
        count.map { $0.formatted() } ?? String(localized: "Unavailable")
    }

    func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var iCloudSettingsGuide: String {
        let notice = String(localized: "iCloud syncing is handled entirely by Apple. HistoryLib cannot see the current sync progress, force a sync, or control which records sync and when.")
        let directions = String(localized: "Tap OK to open system settings. Select your Apple Account, then iCloud, then See All, and change HistoryLib. HistoryLib cannot read this system switch directly.")
        return "\(notice)\n\n\(directions)"
    }

    func openSystemSettings() {
#if os(macOS)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
#else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
#endif
    }
}
