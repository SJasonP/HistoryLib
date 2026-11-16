import Foundation
import SwiftData

struct HistoryExporter {
    let calendar: Calendar
    let fetchChunkSize = 1_000
    let hlChunkTargetRecords = 50_000

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func prepareExportFile(
        modelContext: ModelContext,
        format: HistoryExportFormat,
        split: HistoryExportSplit,
        password: String? = nil,
        progress: ((HistoryExportProgress) -> Void)? = nil
    ) async throws -> PreparedExportFile {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("Export", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        HistoryLibSensitiveFiles.applyAttributes(to: tempRoot)

        let totalRecords = try countAllItems(modelContext: modelContext)
        progress?(.init(phase: .preparing, fraction: 0.02, message: String(localized: "Preparing export...")))
        try Task.checkCancellation()

        do {
            switch format {
            case .historyLib:
                return try await prepareHistoryLibExport(
                    modelContext: modelContext,
                    totalRecords: totalRecords,
                    tempRoot: tempRoot,
                    password: password,
                    progress: progress
                )
            case .safari:
                return try await prepareSafariExport(
                    modelContext: modelContext,
                    totalRecords: totalRecords,
                    split: split,
                    tempRoot: tempRoot,
                    progress: progress
                )
            case .googleTakeout:
                return try await prepareGoogleTakeoutExport(
                    modelContext: modelContext,
                    totalRecords: totalRecords,
                    tempRoot: tempRoot,
                    progress: progress
                )
            }
        } catch {
            try? fileManager.removeItem(at: tempRoot)
            throw error
        }
    }
}
