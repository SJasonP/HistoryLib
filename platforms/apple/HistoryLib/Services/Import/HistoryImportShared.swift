import Foundation
import SwiftData

// Shared deduplication and decoding utilities used by every importer and by the
// background duplicate cleaner. Keep this the single source of truth: do not
// re-implement URL normalization, dedup signatures, flexible decoding, or
// chunking inside individual importers.

// MARK: - Dedup signatures

struct DedupEntry {
    let signature: String
    let visitedSecond: Int64
    let normalizedURL: String
    let normalizedBrowser: String
}

// Pure, stateless helpers — explicitly nonisolated so the background duplicate
// cleaner (an actor) can call them. Under "main actor by default" isolation they
// would otherwise be MainActor-isolated.
enum ImportDedup {
    nonisolated static func makeEntry(rawURL: String, visitedAt: Date, browserName: String) -> DedupEntry {
        let normalizedURL = normalizeURLForDedup(rawURL)
        let normalizedBrowser = browserName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let visitedSecond = Int64(visitedAt.timeIntervalSince1970.rounded(.down))

        return DedupEntry(
            signature: makeSignature(
                normalizedURL: normalizedURL,
                visitedSecond: visitedSecond,
                normalizedBrowser: normalizedBrowser
            ),
            visitedSecond: visitedSecond,
            normalizedURL: normalizedURL,
            normalizedBrowser: normalizedBrowser
        )
    }

    nonisolated static func makeSignature(normalizedURL: String, visitedSecond: Int64, normalizedBrowser: String) -> String {
        "\(normalizedURL)|\(visitedSecond)|\(normalizedBrowser)"
    }

    nonisolated static func nearDuplicateSignatures(for entry: DedupEntry, toleranceSeconds: Int64) -> [String] {
        guard toleranceSeconds > 0 else {
            return [entry.signature]
        }

        var signatures: [String] = []
        signatures.reserveCapacity(Int((toleranceSeconds * 2) + 1))

        let lowerBound = entry.visitedSecond - toleranceSeconds
        let upperBound = entry.visitedSecond + toleranceSeconds
        for second in lowerBound...upperBound {
            signatures.append(makeSignature(
                normalizedURL: entry.normalizedURL,
                visitedSecond: second,
                normalizedBrowser: entry.normalizedBrowser
            ))
        }
        return signatures
    }

    nonisolated static func normalizeURLForDedup(_ rawURL: String) -> String {
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

// MARK: - Pending record + dedup-aware insertion

struct PendingImportRecord {
    let uniqueKey: String
    let dedup: DedupEntry
    let url: String
    let title: String
    let visitedAt: Date
    let visitCount: Int
    let browserName: String
    let sourceFileName: String
    let rawTimeUsec: Int64
    let sourceURL: String?
    let sourceTimeUsec: Int64?
    let destinationURL: String?
    let destinationTimeUsec: Int64?
    let latestVisitWasHTTPGet: Bool?
    let importedAt: Date
}

struct ImportFlushResult {
    let imported: Int
    let skipped: Int
}

enum ImportDeduplicator {
    private static let signatureLookupChunkSize = 800

    /// Inserts pending records, deduplicating against already-stored and
    /// already-accepted records. Duplicates are merged (visit counts summed)
    /// rather than discarded, then counted as skipped inserts.
    static func flush(
        _ pendingRecords: inout [PendingImportRecord],
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions
    ) throws -> ImportFlushResult {
        guard !pendingRecords.isEmpty else {
            return ImportFlushResult(imported: 0, skipped: 0)
        }

        let tolerance = max(dedupOptions.nearDuplicateToleranceSeconds, 0)
        let nearEnabled = dedupOptions.enableNearDuplicateTolerance && tolerance > 0

        var lookupKeys = Set(pendingRecords.map(\.uniqueKey))
        if nearEnabled {
            for pending in pendingRecords {
                lookupKeys.formUnion(ImportDedup.nearDuplicateSignatures(for: pending.dedup, toleranceSeconds: tolerance))
            }
        }
        let existingItemsByKey = try fetchExistingItems(lookupKeys, modelContext: modelContext)

        var acceptedItemsByKey: [String: Item] = [:]
        var imported = 0
        var skipped = 0
        var didMutate = false

        for pending in pendingRecords {
            if let match = matchItem(
                for: pending,
                tolerance: tolerance,
                nearEnabled: nearEnabled,
                accepted: acceptedItemsByKey,
                existing: existingItemsByKey
            ) {
                match.visitCount = max(1, match.visitCount + pending.visitCount)
                skipped += 1
                didMutate = true
                continue
            }

            let item = Item(
                uniqueKey: pending.uniqueKey,
                url: pending.url,
                title: pending.title,
                visitedAt: pending.visitedAt,
                visitCount: pending.visitCount,
                sourceBrowser: pending.browserName,
                sourceFileName: pending.sourceFileName,
                rawTimeUsec: pending.rawTimeUsec,
                sourceURL: pending.sourceURL,
                sourceTimeUsec: pending.sourceTimeUsec,
                destinationURL: pending.destinationURL,
                destinationTimeUsec: pending.destinationTimeUsec,
                latestVisitWasHTTPGet: pending.latestVisitWasHTTPGet,
                importedAt: pending.importedAt
            )
            modelContext.insert(item)
            acceptedItemsByKey[pending.uniqueKey] = item
            if nearEnabled {
                acceptedItemsByKey[pending.dedup.signature] = item
            }
            imported += 1
            didMutate = true
        }

        if didMutate {
            try modelContext.save()
        }

        pendingRecords.removeAll(keepingCapacity: true)
        return ImportFlushResult(imported: imported, skipped: skipped)
    }

    private static func matchItem(
        for pending: PendingImportRecord,
        tolerance: Int64,
        nearEnabled: Bool,
        accepted: [String: Item],
        existing: [String: Item]
    ) -> Item? {
        if let match = accepted[pending.uniqueKey] ?? existing[pending.uniqueKey] {
            return match
        }
        if nearEnabled {
            for signature in ImportDedup.nearDuplicateSignatures(for: pending.dedup, toleranceSeconds: tolerance) {
                if let match = accepted[signature] ?? existing[signature] {
                    return match
                }
            }
        }
        return nil
    }

    private static func fetchExistingItems(
        _ keys: Set<String>,
        modelContext: ModelContext
    ) throws -> [String: Item] {
        guard !keys.isEmpty else { return [:] }

        var map: [String: Item] = [:]
        for chunk in Array(keys).chunked(into: signatureLookupChunkSize) {
            let chunkArray = Array(chunk)
            let descriptor = FetchDescriptor<Item>(
                predicate: #Predicate<Item> { item in
                    chunkArray.contains(item.uniqueKey)
                }
            )
            for item in try modelContext.fetch(descriptor) {
                map[item.uniqueKey] = item
            }
        }
        return map
    }
}

// MARK: - Shared decoding helpers

extension Array {
    nonisolated func chunked(into size: Int) -> [ArraySlice<Element>] {
        guard size > 0 else { return [self[...]] }

        var result: [ArraySlice<Element>] = []
        result.reserveCapacity((count / size) + 1)

        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(self[start..<end])
            start = end
        }
        return result
    }
}

extension KeyedDecodingContainer {
    nonisolated func decodeFlexibleInt64IfPresent(forKey key: Key) -> Int64? {
        if let intVal = try? decode(Int64.self, forKey: key) {
            return intVal
        }
        if let intVal = try? decode(Int.self, forKey: key) {
            return Int64(intVal)
        }
        if let strVal = try? decode(String.self, forKey: key),
           let intVal = Int64(strVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intVal
        }
        return nil
    }

    nonisolated func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        if let intVal = try? decode(Int.self, forKey: key) {
            return intVal
        }
        if let int64Val = try? decode(Int64.self, forKey: key) {
            return Int(int64Val)
        }
        if let strVal = try? decode(String.self, forKey: key),
           let intVal = Int(strVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intVal
        }
        return nil
    }
}
