import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

extension HistoryExporter {
    func prepareHistoryLibExport(
        modelContext: ModelContext,
        totalRecords: Int,
        tempRoot: URL,
        progress: ((HistoryExportProgress) -> Void)?
    ) async throws -> PreparedExportFile {
        let fileManager = FileManager.default
        let exportTime = Date()

        let archiveRoot = tempRoot.appendingPathComponent("archive", isDirectory: true)
        let chunksDirectory = archiveRoot.appendingPathComponent("chunks", isDirectory: true)
        let indexesDirectory = archiveRoot.appendingPathComponent("indexes", isDirectory: true)
        let summaryDirectory = archiveRoot.appendingPathComponent("summary", isDirectory: true)

        try fileManager.createDirectory(at: chunksDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: indexesDirectory, withIntermediateDirectories: true)

        var totalRecordCount = 0
        var globalMinTs: Int64?
        var globalMaxTs: Int64?
        var chunkEntries: [HLChunkIndexEntry] = []
        var currentChunkRecords: [HLRecord] = []
        var currentChunkMinTs: Int64?
        var currentChunkMaxTs: Int64?
        var nextChunkID = 1

        var yearStats: [Int: TimeBucketStats] = [:]
        var monthStats: [String: TimeBucketStats] = [:]
        var dayStats: [String: TimeBucketStats] = [:]

        var processedRecords = 0
        try await enumerateAllItems(modelContext: modelContext) { item in
            let tsUsec = recordTimeUsec(from: item)
            let record = HLRecord(from: item, tsUsec: tsUsec)

            totalRecordCount += 1
            if let minTs = globalMinTs {
                globalMinTs = min(minTs, tsUsec)
            } else {
                globalMinTs = tsUsec
            }
            if let maxTs = globalMaxTs {
                globalMaxTs = max(maxTs, tsUsec)
            } else {
                globalMaxTs = tsUsec
            }

            let year = calendar.component(.year, from: item.visitedAt)
            let month = monthString(from: item.visitedAt)
            let day = dayString(from: item.visitedAt)
            yearStats[year, default: TimeBucketStats()].add(tsUsec)
            monthStats[month, default: TimeBucketStats()].add(tsUsec)
            dayStats[day, default: TimeBucketStats()].add(tsUsec)

            currentChunkRecords.append(record)
            if let chunkMin = currentChunkMinTs {
                currentChunkMinTs = min(chunkMin, tsUsec)
            } else {
                currentChunkMinTs = tsUsec
            }
            if let chunkMax = currentChunkMaxTs {
                currentChunkMaxTs = max(chunkMax, tsUsec)
            } else {
                currentChunkMaxTs = tsUsec
            }

            if currentChunkRecords.count >= hlChunkTargetRecords {
                let entry = try writeHLChunk(
                    id: nextChunkID,
                    records: currentChunkRecords,
                    minTs: currentChunkMinTs ?? tsUsec,
                    maxTs: currentChunkMaxTs ?? tsUsec,
                    chunksDirectory: chunksDirectory
                )
                chunkEntries.append(entry)
                nextChunkID += 1
                currentChunkRecords.removeAll(keepingCapacity: true)
                currentChunkMinTs = nil
                currentChunkMaxTs = nil
            }
        } onItemProcessed: {
            processedRecords += 1
            reportExportProgress(
                phase: .exporting,
                processed: processedRecords,
                total: totalRecords,
                start: 0.05,
                end: 0.86,
                progress: progress
            )
        }

        if !currentChunkRecords.isEmpty {
            let minTs = currentChunkMinTs ?? globalMinTs ?? 0
            let maxTs = currentChunkMaxTs ?? globalMaxTs ?? minTs
            let entry = try writeHLChunk(
                id: nextChunkID,
                records: currentChunkRecords,
                minTs: minTs,
                maxTs: maxTs,
                chunksDirectory: chunksDirectory
            )
            chunkEntries.append(entry)
            currentChunkRecords.removeAll(keepingCapacity: false)
        }

        let chunkIndexPath = "indexes/chunks.json"
        let yearsIndexPath = "indexes/years.json"
        let monthsIndexPath = "indexes/months.json"
        let daysIndexPath = "indexes/days.json"

        try writeJSON(chunkEntries, to: indexesDirectory.appendingPathComponent("chunks.json"))
        try writeJSON(
            yearStats
                .map { HLYearIndexEntry(year: $0.key, recordCount: $0.value.count, minTs: $0.value.minTs, maxTs: $0.value.maxTs) }
                .sorted { $0.year < $1.year },
            to: indexesDirectory.appendingPathComponent("years.json")
        )
        try writeJSON(
            monthStats
                .map { HLMonthIndexEntry(month: $0.key, recordCount: $0.value.count, minTs: $0.value.minTs, maxTs: $0.value.maxTs) }
                .sorted { $0.month < $1.month },
            to: indexesDirectory.appendingPathComponent("months.json")
        )
        try writeJSON(
            dayStats
                .map { HLDayIndexEntry(day: $0.key, recordCount: $0.value.count, minTs: $0.value.minTs, maxTs: $0.value.maxTs) }
                .sorted { $0.day < $1.day },
            to: indexesDirectory.appendingPathComponent("days.json")
        )

        var summaryPath: String?
        var featureFlags = ["prebuilt_time_indexes_v1"]
        if let snapshot = try latestSummarySnapshot(modelContext: modelContext) {
            try fileManager.createDirectory(at: summaryDirectory, withIntermediateDirectories: true)
            summaryPath = "summary/snapshot.json"
            featureFlags.append("summary_snapshot_v1")
            let payload = HLSummarySnapshotPayload(from: snapshot)
            try writeJSON(payload, to: summaryDirectory.appendingPathComponent("snapshot.json"))
        }

        let manifest = HLManifest(
            format: "historylib",
            formatVersion: 1,
            createdAtUsec: Int64((exportTime.timeIntervalSince1970 * 1_000_000).rounded()),
            appName: "HistoryLib",
            appVersion: Self.bundleAppVersion,
            recordSchema: "hl_record_v1",
            recordCount: totalRecordCount,
            chunkCount: chunkEntries.count,
            timeRangeUsec: HLTimeRangeUsec(min: globalMinTs ?? 0, max: globalMaxTs ?? 0),
            chunkEncoding: "jsonl",
            chunkTargetRecords: hlChunkTargetRecords,
            featureFlags: featureFlags,
            indexes: HLManifestIndexes(
                chunks: chunkIndexPath,
                years: yearsIndexPath,
                months: monthsIndexPath,
                days: daysIndexPath
            ),
            summary: summaryPath
        )

        try writeJSON(manifest, to: archiveRoot.appendingPathComponent("manifest.json"))

        progress?(.init(phase: .packaging, fraction: 0.92, message: String(localized: "Compressing archive...")))
        try Task.checkCancellation()
        let hlzURL = tempRoot.appendingPathComponent("historylib-export.hlz")
        try zipDirectory(at: archiveRoot, to: hlzURL)
        progress?(.init(phase: .packaging, fraction: 1.0, message: String(localized: "Export complete.")))

        return PreparedExportFile(
            fileURL: hlzURL,
            contentType: .data,
            defaultFilename: "historylib-export.hlz",
            cleanupDirectoryURL: tempRoot
        )
    }

    func writeHLChunk(
        id: Int,
        records: [HLRecord],
        minTs: Int64,
        maxTs: Int64,
        chunksDirectory: URL
    ) throws -> HLChunkIndexEntry {
        let encoder = JSONEncoder()
        let fileName = String(format: "%08d.jsonl", id)
        let fileURL = chunksDirectory.appendingPathComponent(fileName)

        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()
        for record in records {
            var line = try encoder.encode(record)
            line.append(0x0A)

            if #available(iOS 13.4, macOS 10.15.4, *) {
                try fileHandle.write(contentsOf: line)
            } else {
                fileHandle.write(line)
            }
            hasher.update(data: line)
        }

        let digest = hasher.finalize()
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()

        return HLChunkIndexEntry(
            id: id,
            path: "chunks/\(fileName)",
            recordCount: records.count,
            minTs: minTs,
            maxTs: maxTs,
            sha256: sha256
        )
    }

    func latestSummarySnapshot(modelContext: ModelContext) throws -> SummarySnapshot? {
        var descriptor = FetchDescriptor<SummarySnapshot>(
            sortBy: [SortDescriptor(\SummarySnapshot.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// The app's marketing version, read from the bundle at export time.
    static var bundleAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}
