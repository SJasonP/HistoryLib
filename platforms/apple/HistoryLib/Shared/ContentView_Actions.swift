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

    enum BlockedAction {
        case importHistory
        case deleteRecords

        var localized: String {
            switch self {
            case .importHistory:
                return String(localized: "import")
            case .deleteRecords:
                return String(localized: "delete records")
            }
        }
    }

    private func blockedMutationMessage(for action: BlockedAction) -> String {
        if persistenceBackend == "memoryFallback" { return storageModeMessage }
        let actionText = action.localized
        return String(localized: "Cannot \(actionText) because iCloud is unavailable. Changes are paused to keep your history consistent.")
    }

    func startImport() {
        isFileImporterPresented = true
    }

    /// Copies a picked file or folder into the app's own temporary container and
    /// returns the local copy's URL. Uses a coordinated read inside the
    /// security-scoped access window so iCloud items are materialized and the
    /// sandbox permits the copy. The caller owns cleanup of the returned URL's
    /// parent staging directory.
    func stageImportedItem(_ sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("Staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let destinationURL = stagingRoot.appendingPathComponent(sourceURL.lastPathComponent)

        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { readURL in
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: readURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }
        if let copyError { throw copyError }
        if let coordinatorError { throw coordinatorError }

        var mutableDestinationURL = destinationURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableDestinationURL.setResourceValues(values)
#if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: destinationURL.path
        )
#endif
        return destinationURL
    }

    func handleImporterResult(_ result: Result<URL, Error>) {
        guard canMutateHistoryData else {
            importFeedbackMessage = blockedMutationMessage(for: .importHistory)
            showingImportFeedback = true
            return
        }
        guard !isImporting else { return }

        let url: URL
        do {
            url = try result.get()
        } catch {
            importFeedbackMessage = error.localizedDescription
            showingImportFeedback = true
            return
        }

        isImporting = true
        isCancellingImport = false
        importProgressFraction = nil
        importProgressMessage = String(localized: "Preparing import...")

        importTask = Task { @MainActor in
            var stagedURL: URL?
            var retainStagedItem = false
            defer {
                if let stagedURL, !retainStagedItem {
                    try? FileManager.default.removeItem(at: stagedURL.deletingLastPathComponent())
                }
                isImporting = false
                isCancellingImport = false
                importTask = nil
            }

            // Let the progress overlay paint before the (potentially heavy) copy.
            await Task.yield()

            do {
                // Copy the picked item into our own container first, then import
                // from the local copy. The picked URL is security-scoped and lives
                // elsewhere (Files / iCloud Drive); reading or memory-mapping it in
                // place can be denied by the sandbox on iOS. Working on a local
                // copy avoids that and any security-scope lifetime issues.
                let localURL = try stageImportedItem(url)
                stagedURL = localURL

                if HistoryLibEncryptedArchive.isEncryptedArchive(localURL) {
                    retainStagedItem = true
                    pendingEncryptedImportURL = localURL
                    importArchivePassword = ""
                    importPasswordErrorMessage = ""
                    showingImportPasswordPrompt = true
                    return
                }

                let report = try await importer.importFrom(
                    url: localURL,
                    modelContext: modelContext,
                    progress: { progress in
                        importProgressFraction = progress.fraction
                        importProgressMessage = progress.message
                    }
                )

                applyImportReport(report)
            } catch is CancellationError {
                // User cancelled. Any records imported before cancellation remain;
                // re-importing is safe because import deduplicates.
                scheduleDerivedDataRefresh()
            } catch {
                importFeedbackMessage = error.localizedDescription
                showingImportFeedback = true
            }
        }
    }

    func submitPasswordProtectedImport() {
        guard let stagedURL = pendingEncryptedImportURL, !isImporting else { return }
        let password = HistoryLibEncryptedArchive.normalizedPassword(importArchivePassword)
        guard !password.isEmpty else { return }

        showingImportPasswordPrompt = false
        importArchivePassword = ""
        importPasswordErrorMessage = ""
        isImporting = true
        isCancellingImport = false
        importProgressFraction = nil
        importProgressMessage = String(localized: "Decrypting archive...")

        importTask = Task { @MainActor in
            var retainStagedItem = false
            defer {
                if !retainStagedItem {
                    cleanupPendingEncryptedImport()
                }
                isImporting = false
                isCancellingImport = false
                importTask = nil
            }

            do {
                let report = try await importer.importFrom(
                    url: stagedURL,
                    modelContext: modelContext,
                    password: password,
                    progress: { progress in
                        importProgressFraction = progress.fraction
                        importProgressMessage = progress.message
                    }
                )
                applyImportReport(report)
            } catch is CancellationError {
                scheduleDerivedDataRefresh()
            } catch HistoryLibEncryptedArchiveError.authenticationFailed {
                retainStagedItem = true
                importPasswordErrorMessage = String(localized: "The password is incorrect or the archive is damaged.")
                showingImportPasswordPrompt = true
            } catch {
                importFeedbackMessage = error.localizedDescription
                showingImportFeedback = true
            }
        }
    }

    func cancelPasswordProtectedImport() {
        showingImportPasswordPrompt = false
        importArchivePassword = ""
        importPasswordErrorMessage = ""
        cleanupPendingEncryptedImport()
    }

    func cleanupPendingEncryptedImport() {
        if let url = pendingEncryptedImportURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        pendingEncryptedImportURL = nil
    }

    func applyImportReport(_ report: HistoryImportReport) {
        importFeedbackMessage = [
            String(localized: "Detected format: \(report.format.title)"),
            String(localized: "Scanned files: \(report.scannedFileCount)"),
            String(localized: "Valid files: \(report.validFileCount)"),
            String(localized: "Imported records: \(report.importedRecordCount)"),
            String(localized: "Skipped records: \(report.skippedRecordCount)"),
            report.failures.isEmpty ? nil : String(localized: "Failed files: \(report.failures.count)")
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        showingImportFeedback = true
        scheduleDerivedDataRefresh()
    }

    func cancelImport() {
        guard isImporting, !isCancellingImport else { return }
        isCancellingImport = true
        importProgressMessage = String(localized: "Cancelling import...")
        importTask?.cancel()
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

    func scheduleBackgroundDedupIfNeeded(reason: String) {
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

            scheduleDerivedDataRefresh()
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
            deleteFeedbackMessage = blockedMutationMessage(for: .deleteRecords)
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
                persistDirectoryCountCacheFromStateIfComplete()
            } catch {
                rollbackOptimisticSingleDelete(item, dayStart: dayStart, dayWasRemoved: removedDayFromDirectory)
                persistDirectoryCountCacheFromStateIfComplete()
                deleteFeedbackMessage = String(localized: "Delete failed: \(error.localizedDescription)")
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
            deleteFeedbackMessage = blockedMutationMessage(for: .deleteRecords)
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

            scheduleDerivedDataRefresh()
            return deletedTotal
        } catch {
            deleteFeedbackMessage = String(localized: "Batch delete failed: \(error.localizedDescription)")
            showingDeleteFeedback = true
            return deletedTotal
        }
    }

    func measureClearCacheStorageUsage() async -> ClearCacheStorageUsage {
        await ClearCacheStorageUsageCalculator.measure(databaseURLs: modelContext.container.configurations.map(\.url))
    }

    func clearCaches() async -> DatabaseJournalMaintenance.Outcome {
        guard !isImporting, !isPreparingExport, !isFileExporterPresented,
              !isFileImporterPresented, !showingImportPasswordPrompt else { return .busy }
        searchReloadTask?.cancel()
        searchLoadTask?.cancel()
        searchGeneration += 1
        searchResults.removeAll(keepingCapacity: false)
        isLoadingSearchResults = false
        hasMoreSearchResults = isSearching
        searchScanOffset = 0
        clearDayCaches()
        directoryBuildTask?.cancel()
        directoryBuildGeneration += 1
        isDirectoryLoading = false
        DirectoryCountCache.clear()
        directoryCountsAreComplete = false
        URLCache.shared.removeAllCachedResponses()
        await FaviconStore.shared.clearAllCache()
        await ClearCacheStorageUsageCalculator.clearCacheDirectories()
        await FaviconStore.shared.ensureCacheDirectoryExists()
        return await DatabaseJournalMaintenance.reclaim(databaseURLs: modelContext.container.configurations.map(\.url))
    }

    func exportHistory(_ format: HistoryExportFormat, _ split: HistoryExportSplit, _ password: String?) {
        guard !isPreparingExport else { return }

        isPreparingExport = true
        isCancellingExport = false
        exportProgressFraction = 0.02
        exportProgressMessage = String(localized: "Preparing export...")

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
                    password: password,
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
                exportFeedbackMessage = String(localized: "Export failed: \(error.localizedDescription)")
                showingExportFeedback = true
            }
        }

        exportPreparationTask = task
    }

    func cancelExportPreparation() {
        guard isPreparingExport, !isCancellingExport else { return }
        isCancellingExport = true
        exportProgressMessage = String(localized: "Cancelling export...")
        exportPreparationTask?.cancel()
    }

    func handleFileExporterCompletion(_ result: Result<URL, Error>) {
        defer { cleanupPreparedExportFiles() }

        switch result {
        case .success:
            exportFeedbackMessage = String(localized: "Export completed.")
            showingExportFeedback = true
        case .failure(let error):
            if isUserCancelledFileExport(error) {
                return
            }
            exportFeedbackMessage = String(localized: "Export failed: \(error.localizedDescription)")
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
