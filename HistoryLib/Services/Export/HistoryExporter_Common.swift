import Foundation
import SwiftData

extension HistoryExporter {
    func enumerateAllItems(
        modelContext: ModelContext,
        handler: (Item) throws -> Void,
        onItemProcessed: (() -> Void)? = nil
    ) async throws {
        var fetchOffset = 0

        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<Item>(
                sortBy: [SortDescriptor(\Item.visitedAt, order: .forward)]
            )
            descriptor.fetchLimit = fetchChunkSize
            descriptor.fetchOffset = fetchOffset

            let batch = try modelContext.fetch(descriptor)
            if batch.isEmpty {
                break
            }

            for (index, item) in batch.enumerated() {
                try handler(item)
                onItemProcessed?()
                if index.isMultiple(of: 200) {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            }

            fetchOffset += batch.count
            if batch.count < fetchChunkSize {
                break
            }
        }
    }

    func countAllItems(modelContext: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Item>()
        return try modelContext.fetchCount(descriptor)
    }

    func reportExportProgress(
        phase: HistoryExportProgress.Phase,
        processed: Int,
        total: Int,
        start: Double,
        end: Double,
        progress: ((HistoryExportProgress) -> Void)?
    ) {
        guard total > 0 else {
            progress?(.init(phase: phase, fraction: end, message: "Exporting records..."))
            return
        }

        let ratio = min(max(Double(processed) / Double(total), 0), 1)
        let fraction = start + (end - start) * ratio
        progress?(.init(phase: phase, fraction: fraction, message: "Exporting records (\(processed)/\(total))..."))
    }

    func safariGroupedRelativePath(for date: Date, split: HistoryExportSplit) -> String {
        switch split {
        case .single:
            return "all.json"
        case .year:
            return "\(yearString(from: date)).json"
        case .month:
            return "\(yearString(from: date))/\(monthString(from: date)).json"
        case .day:
            return "\(yearString(from: date))/\(monthString(from: date))/\(dayString(from: date)).json"
        }
    }

    func yearString(from date: Date) -> String {
        let year = calendar.component(.year, from: date)
        return String(format: "%04d", year)
    }

    func monthString(from date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    func dayString(from date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    func zipDirectory(at directoryURL: URL, to zipURL: URL) throws {
        try MinimalZipArchive.createZip(fromDirectory: directoryURL, to: zipURL)
    }

    func writeJSON<T: Encodable>(_ value: T, to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }
}
