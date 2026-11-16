import Foundation
import SwiftData
import UniformTypeIdentifiers

extension HistoryExporter {
    func prepareGoogleTakeoutExport(
        modelContext: ModelContext,
        totalRecords: Int,
        tempRoot: URL,
        progress: ((HistoryExportProgress) -> Void)?
    ) async throws -> PreparedExportFile {
        let fileManager = FileManager.default
        let outputURL = tempRoot.appendingPathComponent("google-takeout.json")
        let writer = try JSONHistoryFileWriter(
            fileURL: outputURL,
            format: .googleTakeout,
            exportTime: Date()
        )
        var processedRecords = 0

        do {
            try await enumerateAllItems(modelContext: modelContext) { item in
                try writer.appendGoogleTakeout(item: item)
            } onItemProcessed: {
                processedRecords += 1
                reportExportProgress(
                    phase: .exporting,
                    processed: processedRecords,
                    total: totalRecords,
                    start: 0.05,
                    end: 0.98,
                    progress: progress
                )
            }
            try writer.finish()
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw error
        }

        progress?(.init(phase: .packaging, fraction: 1.0, message: String(localized: "Export complete.")))
        return PreparedExportFile(
            fileURL: outputURL,
            contentType: .json,
            defaultFilename: "google-takeout",
            cleanupDirectoryURL: tempRoot
        )
    }
}
