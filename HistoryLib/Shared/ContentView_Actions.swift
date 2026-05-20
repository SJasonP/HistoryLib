import Foundation
import Network
import SwiftData
import SwiftUI

#if !os(macOS)
import UIKit
#endif

private final class NetworkStatusProbeResolution: @unchecked Sendable {
    private let continuation: CheckedContinuation<NWPath.Status, Never>
    private let monitor: NWPathMonitor
    private let lock = NSLock()
    nonisolated(unsafe) private var resolved = false

    nonisolated init(
        continuation: CheckedContinuation<NWPath.Status, Never>,
        monitor: NWPathMonitor
    ) {
        self.continuation = continuation
        self.monitor = monitor
    }

    nonisolated func finish(with status: NWPath.Status) {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else { return }
        resolved = true
        continuation.resume(returning: status)
        monitor.cancel()
    }
}

extension ContentView {
    private func detectCurrentNetworkPathStatus(timeout: TimeInterval = 1.0) async -> NWPath.Status {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "HistoryLib.NetworkStatusProbe")
            let resolution = NetworkStatusProbeResolution(
                continuation: continuation,
                monitor: monitor
            )

            monitor.pathUpdateHandler = { path in
                resolution.finish(with: path.status)
            }
            monitor.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                resolution.finish(with: monitor.currentPath.status)
            }
        }
    }

    private func blockedMutationMessage(for action: String) -> String {
        let details = persistenceError.trimmingCharacters(in: .whitespacesAndNewlines)
        if details.isEmpty {
            return "Cannot \(action) because CloudKit is unavailable. History changes are blocked to prevent data divergence."
        }
        return "Cannot \(action) because CloudKit is unavailable. History changes are blocked to prevent data divergence.\n\nError: \(details)"
    }

    func startImportAutoDetect() {
        importFormatPreference = .automatic
        isFileImporterPresented = true
    }

    func startImportAsSafari() {
        importFormatPreference = .safari
        isFileImporterPresented = true
    }

    func startImportAsHistoryLib() {
        importFormatPreference = .historyLib
        isFileImporterPresented = true
    }

    func handleImporterResult(_ result: Result<URL, Error>) {
        guard canMutateHistoryData else {
            importFeedbackMessage = blockedMutationMessage(for: "import")
            showingImportFeedback = true
            return
        }

        do {
            let url = try result.get()
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let report = try importer.importFrom(
                url: url,
                modelContext: modelContext,
                preferredFormat: importFormatPreference
            )
            importFeedbackMessage = [
                "Detected format: \(report.format.title)",
                "Scanned files: \(report.scannedFileCount)",
                "Valid files: \(report.validFileCount)",
                "Imported records: \(report.importedRecordCount)",
                "Skipped records: \(report.skippedRecordCount)",
                report.failures.isEmpty ? nil : "Failed files: \(report.failures.count)"
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
            showingImportFeedback = true

            refreshSummaryStats()
            rebuildDirectorySkeleton()
            resetSearchPaginationAndMaybeReload()
            generateAndPersistSummarySnapshot()
        } catch {
            importFeedbackMessage = error.localizedDescription
            showingImportFeedback = true
        }
    }

    func openRecordInBrowserIfNeeded(_ item: Item) {
        guard openRecordInBrowserOnDoubleClick,
              let url = normalizedWebURL(from: item.url) else {
            return
        }
        openURL(url)
    }

    func normalizedWebURL(from rawURL: String) -> URL? {
        if let direct = URL(string: rawURL),
           let scheme = direct.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return direct
        }
        return nil
    }

    func retryICloudSync() {
        Task { @MainActor in
            guard !isSyncing else { return }
            isSyncing = true
            defer { isSyncing = false }

            guard enableICloudSync else {
                syncFeedbackMessage = "iCloud sync is disabled in Settings."
                showingSyncFeedback = true
                return
            }

            guard persistenceBackend == "cloudKit" else {
                syncFeedbackMessage = blockedMutationMessage(for: "check iCloud sync")
                showingSyncFeedback = true
                return
            }

            do {
                let networkStatus = await detectCurrentNetworkPathStatus()
                _ = NSUbiquitousKeyValueStore.default.synchronize()
                let recordCount = try modelContext.fetchCount(FetchDescriptor<Item>())
                let syncLine: String
                switch networkStatus {
                case .satisfied:
                    syncLine = "Network: online. Cloud sync should proceed automatically."
                case .unsatisfied:
                    syncLine = "Network: offline. Changes are queued locally and will sync when network is restored."
                case .requiresConnection:
                    syncLine = "Network: connection required. Changes are queued locally until connectivity is available."
                @unknown default:
                    syncLine = "Network: unknown status. Cloud sync remains system-managed."
                }
                syncFeedbackMessage = """
                CloudKit backend is configured.
                Local record count: \(recordCount)
                \(syncLine)
                """
                showingSyncFeedback = true
                scheduleBackgroundDedupIfNeeded(reason: "manual sync check")
            } catch {
                syncFeedbackMessage = "Sync failed: \(error.localizedDescription)"
                showingSyncFeedback = true
            }
        }
    }

    func scheduleBackgroundDedupIfNeeded(reason: String) {
        guard enableICloudSync else { return }
        guard persistenceBackend == "cloudKit" else { return }
        guard !isBackgroundDedupRunning else { return }
        guard !isPreparingExport else { return }

        let now = Date()
        let minimumInterval: TimeInterval = 180
        guard now.timeIntervalSince(lastBackgroundDedupRunAt) >= minimumInterval else { return }

        backgroundDedupTask?.cancel()
        backgroundDedupTask = Task { @MainActor in
            let networkStatus = await detectCurrentNetworkPathStatus(timeout: 0.7)
            guard networkStatus == .satisfied else { return }
            await runBackgroundDedup(reason: reason)
        }
    }

    func runBackgroundDedup(reason: String) async {
        guard !isBackgroundDedupRunning else { return }
        isBackgroundDedupRunning = true
        defer { isBackgroundDedupRunning = false }

        lastBackgroundDedupRunAt = Date()

        let cleaner = HistoryDuplicateCleaner()

        do {
            let report = try await cleaner.deduplicate(
                modelContainer: modelContext.container,
                dedupOptions: ImportDedupOptions()
            )

            guard !Task.isCancelled else { return }
            guard report.removedCount > 0 else { return }

            refreshSummaryStats()
            rebuildDirectorySkeleton()
            resetSearchPaginationAndMaybeReload()
            generateAndPersistSummarySnapshot()
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG
            print("Background dedup (\(reason)) failed: \(error)")
            #endif
        }
    }

    func deleteSingleRecord(_ item: Item) {
        guard canMutateHistoryData else {
            deleteFeedbackMessage = blockedMutationMessage(for: "delete records")
            showingDeleteFeedback = true
            return
        }

        let dayStart = calendar.startOfDay(for: item.visitedAt)
        let removedDayFromDirectory = applyOptimisticSingleDelete(item, dayStart: dayStart)

        Task { @MainActor in
            do {
                modelContext.delete(item)
                try modelContext.save()
                refreshSummaryStats()
                generateAndPersistSummarySnapshot()
            } catch {
                rollbackOptimisticSingleDelete(item, dayStart: dayStart, dayWasRemoved: removedDayFromDirectory)
                deleteFeedbackMessage = "Delete failed: \(error.localizedDescription)"
                showingDeleteFeedback = true
            }
        }
    }

    func applyOptimisticSingleDelete(_ item: Item, dayStart: Date) -> Bool {
        var removedDayFromDirectory = false

        if var items = dayLoadedItems[dayStart] {
            items.removeAll { $0.persistentModelID == item.persistentModelID }
            dayLoadedItems[dayStart] = items
        }

        searchResults.removeAll { $0.persistentModelID == item.persistentModelID }

        if let count = dayItemCounts[dayStart] {
            let newCount = max(0, count - 1)
            dayItemCounts[dayStart] = newCount

            if newCount == 0 {
                removedDayFromDirectory = directoryDayStarts.contains(dayStart)
                directoryDayStarts.removeAll { $0 == dayStart }
                dayLoadedItems[dayStart] = []
                dayItemOffsets[dayStart] = 0
                dayHasMoreItems[dayStart] = false
                expandedDays.remove(dayStart)
            }
        }

        totalRecordCount = max(0, totalRecordCount - 1)
        if latestSummarySnapshot != nil {
            latestSummarySnapshot?.totalRecords = totalRecordCount
        }

        return removedDayFromDirectory
    }

    func rollbackOptimisticSingleDelete(_ item: Item, dayStart: Date, dayWasRemoved: Bool) {
        insertItemIntoDayLoadedItemsIfNeeded(item, dayStart: dayStart)
        insertItemIntoSearchResultsIfNeeded(item)

        if let count = dayItemCounts[dayStart] {
            dayItemCounts[dayStart] = count + 1
        }

        if dayWasRemoved && !directoryDayStarts.contains(dayStart) {
            directoryDayStarts.append(dayStart)
            directoryDayStarts.sort(by: >)
        }

        totalRecordCount += 1
        if latestSummarySnapshot != nil {
            latestSummarySnapshot?.totalRecords = totalRecordCount
        }
    }

    func insertItemIntoDayLoadedItemsIfNeeded(_ item: Item, dayStart: Date) {
        guard var items = dayLoadedItems[dayStart] else { return }
        if items.contains(where: { $0.persistentModelID == item.persistentModelID }) {
            return
        }

        items.append(item)
        items.sort { $0.visitedAt > $1.visitedAt }
        dayLoadedItems[dayStart] = items
    }

    func insertItemIntoSearchResultsIfNeeded(_ item: Item) {
        guard isSearching else { return }
        if !matchesSearchQuery(item, query: normalizedSearchText) {
            return
        }
        if searchResults.contains(where: { $0.persistentModelID == item.persistentModelID }) {
            return
        }

        searchResults.append(item)
        searchResults.sort { $0.visitedAt > $1.visitedAt }
    }

    func matchesSearchQuery(_ item: Item, query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return item.url.localizedCaseInsensitiveContains(query)
            || item.title.localizedCaseInsensitiveContains(query)
    }

    func countRecords(in range: ClosedRange<Date>) -> Int {
        let start = range.lowerBound
        let end = range.upperBound
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { item in
                item.visitedAt >= start && item.visitedAt <= end
            }
        )

        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            return 0
        }
    }

    func deleteRecordsInRange(_ range: ClosedRange<Date>) -> Int {
        guard canMutateHistoryData else {
            deleteFeedbackMessage = blockedMutationMessage(for: "delete records")
            showingDeleteFeedback = true
            return 0
        }

        let start = range.lowerBound
        let end = range.upperBound
        var deletedTotal = 0

        do {
            while true {
                var descriptor = FetchDescriptor<Item>(
                    predicate: #Predicate<Item> { item in
                        item.visitedAt >= start && item.visitedAt <= end
                    },
                    sortBy: [SortDescriptor(\Item.visitedAt, order: .forward)]
                )
                descriptor.fetchLimit = 500

                let records = try modelContext.fetch(descriptor)
                if records.isEmpty {
                    break
                }

                for item in records {
                    modelContext.delete(item)
                }

                try modelContext.save()
                deletedTotal += records.count
            }

            refreshSummaryStats()
            rebuildDirectorySkeleton()
            resetSearchPaginationAndMaybeReload()
            generateAndPersistSummarySnapshot()
            return deletedTotal
        } catch {
            deleteFeedbackMessage = "Batch delete failed: \(error.localizedDescription)"
            showingDeleteFeedback = true
            return deletedTotal
        }
    }

    func clearFaviconCache() {
        Task { @MainActor in
            await FaviconStore.shared.clearAllCache()
        }
    }

    func exportHistory(_ format: HistoryExportFormat, _ split: HistoryExportSplit) {
        guard !isPreparingExport else { return }

        isPreparingExport = true
        isCancellingExport = false
        exportProgressFraction = 0.02
        exportProgressMessage = "Preparing export..."

        let task = Task {
            defer {
                isPreparingExport = false
                isCancellingExport = false
                exportPreparationTask = nil
            }

            do {
                cleanupPreparedExportFiles()
                let prepared = try await exporter.prepareExportFile(
                    modelContext: modelContext,
                    format: format,
                    split: split,
                    progress: { progress in
                        exportProgressFraction = progress.fraction
                        exportProgressMessage = progress.message
                    }
                )
                try Task.checkCancellation()

                exportDocument = ExportFileDocument(sourceFileURL: prepared.fileURL)
                exportContentType = prepared.contentType
                exportFilename = prepared.defaultFilename
                exportCleanupDirectoryURL = prepared.cleanupDirectoryURL
                isFileExporterPresented = true
            } catch is CancellationError {
                cleanupPreparedExportFiles()
            } catch {
                cleanupPreparedExportFiles()
                exportFeedbackMessage = "Export failed: \(error.localizedDescription)"
                showingExportFeedback = true
            }
        }

        exportPreparationTask = task
    }

    func cancelExportPreparation() {
        guard isPreparingExport, !isCancellingExport else { return }
        isCancellingExport = true
        exportProgressMessage = "Cancelling export..."
        exportPreparationTask?.cancel()
    }

    func handleFileExporterCompletion(_ result: Result<URL, Error>) {
        defer { cleanupPreparedExportFiles() }

        switch result {
        case .success:
            exportFeedbackMessage = "Export completed."
            showingExportFeedback = true
        case .failure(let error):
            if isUserCancelledFileExport(error) {
                return
            }
            exportFeedbackMessage = "Export failed: \(error.localizedDescription)"
            showingExportFeedback = true
        }
    }

    func cleanupPreparedExportFiles() {
        if let cleanupURL = exportCleanupDirectoryURL {
            try? FileManager.default.removeItem(at: cleanupURL)
        }
        exportCleanupDirectoryURL = nil
        exportDocument = nil
    }

    func isUserCancelledFileExport(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return true
        }
        if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
            return true
        }
        return false
    }

#if !os(macOS)
    func openSystemAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(url)
    }
#endif
}
