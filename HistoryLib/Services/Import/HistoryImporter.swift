import Foundation
import SwiftData

final class HistoryImporter {
    private let safariImporter = SafariHistoryImporter()
    private let chromeImporter = ChromeHistoryImporter()
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
        case .chrome:
            return try await chromeImporter.importFrom(
                url: url,
                modelContext: modelContext,
                dedupOptions: dedupOptions,
                progress: progress
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
        // Safari is probed before Chrome: both export a file named History.json,
        // and only a content check tells them apart.
        if safariImporter.looksLikeSafariHistorySource(url) {
            return .safari
        }
        if chromeImporter.looksLikeChromeHistorySource(url) {
            return .chrome
        }
        throw HistoryImportError.unrecognizedFormat
    }
}
