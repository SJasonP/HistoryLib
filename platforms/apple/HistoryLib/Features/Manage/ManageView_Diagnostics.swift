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
            LabeledContent("iCloud Service", value: diagnostics.accountMessage)
            LabeledContent("Sync Activity", value: syncActivityText)
            LabeledContent("Last Synced") {
                if let date = syncActivity.lastSuccessfulTransfer {
                    Text(date, format: .dateTime.year().month().day().hour().minute().second())
                } else {
                    Text("Not Observed")
                }
            }
            Text("Sync time is the latest successful upload or download observed during this app session. It does not confirm that all devices are up to date.")
                .font(.footnote).foregroundStyle(.secondary)
            LabeledContent("Local Records", value: countText(diagnostics.localCount))
            LabeledContent("Cloud Records", value: cloudRecordsText)
            if case .available = diagnostics.cloudRecordsState {
                Text(diagnostics.cloudMessage).font(.footnote).foregroundStyle(.secondary)
            }
            Button("Change iCloud Settings") { showingICloudGuide = true }
        }
    }

    var syncActivityText: String {
        guard syncActivity.isBound else { return String(localized: "Unavailable") }
        if syncActivity.isSyncing { return String(localized: "Syncing…") }
        if syncActivity.hasObservedFailure { return String(localized: "Sync Issue Detected") }
        return String(localized: "No Active Transfer Observed")
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
            Button {
                guard !diagnostics.isClearing else { return }
                showingClearCacheConfirmation = true
            } label: {
                if diagnostics.isClearing { ProgressView() } else { Text("Clear Cache") }
            }
            .disabled(diagnostics.isClearing || isImporting || isPreparingExport)
        }
    }

    var clearCacheConfirmationMessage: String {
        let clearable = diagnostics.storageUsage.map { byteCount($0.clearableCacheBytes) } ?? String(localized: "the disposable cache")
        if showSiteIcons {
            return String(localized: "Continuing will only clear \(clearable) of cache data and turn off Show Site Icons.")
        }
        return String(localized: "Continuing will only clear \(clearable) of cache data.")
    }

    func beginClearCache() {
        guard !diagnostics.isClearing else { return }
        diagnostics.isClearing = true
        showSiteIcons = false
        Task { @MainActor in
            let result: String
            switch await onClearCache() {
            case .completed:
                result = String(localized: "Cache cleared successfully.")
            case .busy:
                result = String(localized: "Cache cleared. Some database journals are busy; try again later.")
            case .unavailable:
                result = String(localized: "Cache cleared. Database journal maintenance could not finish.")
            }
            if monitoringEnabled {
                let usage = await onMeasureStorageUsage()
                if monitoringEnabled { diagnostics.storageUsage = usage }
            }
            diagnostics.isClearing = false
            cacheResultMessage = result
            showingCacheResult = true
        }
    }

    func countText(_ count: Int?) -> String {
        count.map { $0.formatted() } ?? String(localized: "Unavailable")
    }

    var cloudRecordsText: String {
        switch diagnostics.cloudRecordsState {
        case .checking:
            return String(localized: "Checking…")
        case .unavailable:
            return String(localized: "Unavailable")
        case .available(let count):
            return count.formatted()
        }
    }

    func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var iCloudSettingsGuide: String {
        let notice = String(localized: "Apple controls iCloud sync scheduling. HistoryLib can observe sync activity, but cannot force a sync, choose which records sync, or confirm that all devices are up to date.")
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
