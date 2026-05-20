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

    func deduplicate(
        modelContainer: ModelContainer,
        dedupOptions: ImportDedupOptions = ImportDedupOptions()
    ) async throws -> HistoryDuplicateCleanupReport {
        let modelContext = ModelContext(modelContainer)
        let toleranceSeconds: Int64 = dedupOptions.enableNearDuplicateTolerance
            ? max(0, dedupOptions.nearDuplicateToleranceSeconds)
            : 0

        var duplicateIDs: [PersistentIdentifier] = []
        var latestKeptSecondByKey: [String: Int64] = [:]
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

                if let previousKeptSecond = latestKeptSecondByKey[dedupKey],
                   previousKeptSecond >= (visitedSecond - toleranceSeconds) {
                    duplicateIDs.append(item.persistentModelID)
                } else {
                    latestKeptSecondByKey[dedupKey] = visitedSecond
                }

                scannedCount += 1
                sinceLastPrune += 1

                if sinceLastPrune >= pruneInterval {
                    let threshold = visitedSecond - toleranceSeconds
                    latestKeptSecondByKey = latestKeptSecondByKey.filter { $0.value >= threshold }
                    sinceLastPrune = 0
                    await Task.yield()
                }
            }

            scanOffset += batch.count
            if batch.count < fetchBatchSize {
                break
            }
        }

        var removedCount = 0
        for chunk in duplicateIDs.chunked(into: deleteBatchSize) {
            try Task.checkCancellation()
            var deletedInChunk = false

            for id in chunk {
                if let model = modelContext.model(for: id) as? Item {
                    modelContext.delete(model)
                    removedCount += 1
                    deletedInChunk = true
                }
            }

            if deletedInChunk {
                try modelContext.save()
            }

            await Task.yield()
        }

        return HistoryDuplicateCleanupReport(
            scannedCount: scannedCount,
            removedCount: removedCount
        )
    }

    private static func makeDedupKey(url rawURL: String, browserName: String) -> String {
        let normalizedURL = normalizeURLForDedup(rawURL)
        let normalizedBrowser = browserName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(normalizedURL)|\(normalizedBrowser)"
    }

    private static func normalizeURLForDedup(_ rawURL: String) -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        guard let initialURL = URL(string: trimmed),
              var components = URLComponents(url: initialURL, resolvingAgainstBaseURL: false) else {
            return trimmed.lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil

        if let scheme = components.scheme,
           let port = components.port,
           (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
            components.port = nil
        }

        if components.path.isEmpty {
            components.path = "/"
        } else if components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        return components.string ?? trimmed.lowercased()
    }
}

private extension Array {
    nonisolated func chunked(into size: Int) -> [ArraySlice<Element>] {
        guard size > 0 else { return [self[...]] }

        var chunks: [ArraySlice<Element>] = []
        chunks.reserveCapacity((count / size) + 1)

        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(self[start..<end])
            start = end
        }

        return chunks
    }
}
