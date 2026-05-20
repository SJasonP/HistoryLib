import Foundation
import SwiftData
import UniformTypeIdentifiers

extension HistoryExporter {
    func prepareSafariExport(
        modelContext: ModelContext,
        totalRecords: Int,
        split: HistoryExportSplit,
        tempRoot: URL,
        progress: ((HistoryExportProgress) -> Void)?
    ) async throws -> PreparedExportFile {
        let fileManager = FileManager.default
        let exportTime = Date()
        let baseFilename = "safari-export-\(split.token)"
        var processedRecords = 0

        let payloadDirectoryURL = tempRoot.appendingPathComponent("payload", isDirectory: true)
        try fileManager.createDirectory(at: payloadDirectoryURL, withIntermediateDirectories: true)

        var currentRelativePath: String?
        var currentWriter: JSONHistoryFileWriter?

        try await enumerateAllItems(modelContext: modelContext) { item in
            let relativePath = safariGroupedRelativePath(for: item.visitedAt, split: split)
            if currentRelativePath != relativePath {
                try currentWriter?.finish()
                currentRelativePath = relativePath

                let outputURL = payloadDirectoryURL.appendingPathComponent(relativePath)
                let parent = outputURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                currentWriter = try JSONHistoryFileWriter(fileURL: outputURL, format: .safari, exportTime: exportTime)
            }

            try currentWriter?.appendSafari(item: item)
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

        if currentWriter == nil {
            let outputURL = payloadDirectoryURL.appendingPathComponent("empty.json")
            currentWriter = try JSONHistoryFileWriter(fileURL: outputURL, format: .safari, exportTime: exportTime)
        }

        try currentWriter?.finish()

        progress?(.init(phase: .packaging, fraction: 0.92, message: "Compressing archive..."))
        try Task.checkCancellation()
        let zipURL = tempRoot.appendingPathComponent("\(baseFilename).zip")
        try zipDirectory(at: payloadDirectoryURL, to: zipURL)
        progress?(.init(phase: .packaging, fraction: 1.0, message: "Export complete."))

        return PreparedExportFile(
            fileURL: zipURL,
            contentType: .zip,
            defaultFilename: baseFilename,
            cleanupDirectoryURL: tempRoot
        )
    }
}
