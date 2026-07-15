import Foundation
import SwiftData

final class HistoryImporter {
    private let safariImporter = SafariHistoryImporter()
    private let historyLibImporter = HistoryLibArchiveImporter()

    func importFrom(
        url: URL,
        modelContext: ModelContext,
        password: String? = nil,
        dedupOptions: ImportDedupOptions = ImportDedupOptions(),
        progress: HistoryImportProgressHandler? = nil
    ) async throws -> HistoryImportReport {
        let resolvedFormat = try resolveFormat(url: url)

        switch resolvedFormat {
        case .safari:
            let report = try await safariImporter.importFrom(
                url: url,
                modelContext: modelContext,
                dedupOptions: dedupOptions,
                progress: progress
            )
            return HistoryImportReport(
                format: .safari,
                scannedFileCount: report.scannedJSONFileCount,
                validFileCount: report.validJSONFileCount,
                importedRecordCount: report.importedRecordCount,
                skippedRecordCount: report.skippedRecordCount,
                failures: report.failures
            )
        case .historyLib:
            return try await historyLibImporter.importFrom(
                url: url,
                modelContext: modelContext,
                password: password,
                dedupOptions: dedupOptions,
                progress: progress
            )
        }
    }

    private func resolveFormat(url: URL) throws -> HistoryImportFormatResolved {
        if historyLibImporter.looksLikeHistoryLibSource(url) {
            return .historyLib
        }
        if safariImporter.looksLikeSafariHistorySource(url) {
            return .safari
        }
        throw HistoryImportError.unrecognizedFormat
    }
}
