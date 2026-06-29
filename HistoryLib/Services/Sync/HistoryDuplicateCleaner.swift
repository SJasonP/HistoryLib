import Foundation
import SwiftData

struct HistoryDuplicateCleanupReport: Sendable {
    let scannedCount: Int
    let removedCount: Int
}

actor HistoryDuplicateCleaner {
    private let fetchBatchSize: Int
    private let deleteBatchSize: Int
    private let pruneInterval: Int

    init(
        fetchBatchSize: Int = 2_000,
        deleteBatchSize: Int = 1_000,
        pruneInterval: Int = 5_000
    ) {
        self.fetchBatchSize = max(200, fetchBatchSize)
        self.deleteBatchSize = max(100, deleteBatchSize)
        self.pruneInterval = max(500, pruneInterval)
    }

    private struct KeptRecord {
        let visitedSecond: Int64
        let id: PersistentIdentifier
    }

    func deduplicate(
        modelContainer: ModelContainer,
        dedupOptions: ImportDedupOptions = ImportDedupOptions()
    ) async throws -> HistoryDuplicateCleanupReport {
        let modelContext = ModelContext(modelContainer)
        let toleranceSeconds: Int64 = dedupOptions.enableNearDuplicateTolerance
            ? max(0, dedupOptions.nearDuplicateToleranceSeconds)
            : 0

        var duplicateIDs: [PersistentIdentifier] = []
        var mergeVisitsByKeptID: [PersistentIdentifier: Int] = [:]
        var keptByKey: [String: KeptRecord] = [:]
        var scanOffset = 0
        var scannedCount = 0
        var sinceLastPrune = 0

        while true {
            try Task.checkCancellation()

            var descriptor = FetchDescriptor<Item>(
                sortBy: [SortDescriptor(\Item.visitedAt, order: .forward)]
            )
            descriptor.fetchOffset = scanOffset
            descriptor.fetchLimit = fetchBatchSize

            let batch = try modelContext.fetch(descriptor)
            if batch.isEmpty {
                break
            }

            for item in batch {
                let visitedSecond = Int64(item.visitedAt.timeIntervalSince1970.rounded(.down))
                let dedupKey = Self.makeDedupKey(
                    url: item.url,
                    browserName: item.sourceBrowser
                )

                if let kept = keptByKey[dedupKey],
                   kept.visitedSecond >= (visitedSecond - toleranceSeconds) {
                    // Duplicate: merge its visit count into the kept record instead
                    // of discarding it, then mark it for removal.
                    duplicateIDs.append(item.persistentModelID)
                    mergeVisitsByKeptID[kept.id, default: 0] += max(1, item.visitCount)
                } else {
                    keptByKey[dedupKey] = KeptRecord(visitedSecond: visitedSecond, id: item.persistentModelID)
                }

                scannedCount += 1
                sinceLastPrune += 1

                if sinceLastPrune >= pruneInterval {
                    let threshold = visitedSecond - toleranceSeconds
                    keptByKey = keptByKey.filter { $0.value.visitedSecond >= threshold }
                    sinceLastPrune = 0
                    await Task.yield()
                }
            }

            scanOffset += batch.count
            if batch.count < fetchBatchSize {
                break
            }
        }

        // Merge the accumulated visit counts into the kept records.
        for (keptID, addedVisits) in mergeVisitsByKeptID {
            if let kept = modelContext.model(for: keptID) as? Item {
                kept.visitCount = max(1, kept.visitCount + addedVisits)
            }
        }

        var removedCount = 0
        for chunk in duplicateIDs.chunked(into: deleteBatchSize) {
            try Task.checkCancellation()
            var changed = false

            for id in chunk {
                if let model = modelContext.model(for: id) as? Item {
                    modelContext.delete(model)
                    removedCount += 1
                    changed = true
                }
            }

            if changed {
                try modelContext.save()
            }

            await Task.yield()
        }

        // Persist any merged visit counts that the delete loop did not already save.
        if modelContext.hasChanges {
            try modelContext.save()
        }

        return HistoryDuplicateCleanupReport(
            scannedCount: scannedCount,
            removedCount: removedCount
        )
    }

    private static func makeDedupKey(url rawURL: String, browserName: String) -> String {
        let normalizedURL = ImportDedup.normalizeURLForDedup(rawURL)
        let normalizedBrowser = browserName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(normalizedURL)|\(normalizedBrowser)"
    }
}
