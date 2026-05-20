import Foundation
import SwiftData

final class HistoryImporter {
    private let safariImporter = SafariHistoryImporter()
    private let historyLibImporter = HistoryLibArchiveImporter()

    func importFrom(
        url: URL,
        modelContext: ModelContext,
        preferredFormat: HistoryImportFormatPreference = .automatic,
        dedupOptions: ImportDedupOptions = ImportDedupOptions()
    ) throws -> HistoryImportReport {
        let resolvedFormat = resolveFormat(url: url, preferredFormat: preferredFormat)

        switch resolvedFormat {
        case .safari:
            let report = try safariImporter.importFrom(
                url: url,
                modelContext: modelContext,
                dedupOptions: dedupOptions
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
            return try historyLibImporter.importFrom(
                url: url,
                modelContext: modelContext,
                dedupOptions: dedupOptions
            )
        }
    }

    private func resolveFormat(
        url: URL,
        preferredFormat: HistoryImportFormatPreference
    ) -> HistoryImportFormatResolved {
        switch preferredFormat {
        case .automatic:
            return historyLibImporter.looksLikeHistoryLibSource(url) ? .historyLib : .safari
        case .safari:
            return .safari
        case .historyLib:
            return .historyLib
        }
    }
}
