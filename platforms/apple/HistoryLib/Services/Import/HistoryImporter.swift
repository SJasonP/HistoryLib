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
        // ZIP inspection shares the bounded disk extractor with import. Never
        // inflate an unknown JSON member into memory just to identify a format.
        var sourceURL = url
        var extractionRoot: URL?
        defer { if let extractionRoot { try? FileManager.default.removeItem(at: extractionRoot) } }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if !isDirectory, url.pathExtension.lowercased() == "zip", !HistoryLibEncryptedArchive.isEncryptedArchive(url) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("Import", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            extractionRoot = root
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            HistoryLibSensitiveFiles.applyAttributes(to: root)
            try await ImportZipArchive.extractInBackground(at: url, to: root)
            sourceURL = root
        }
        let resolvedFormat = try await resolveFormat(url: sourceURL)

        switch resolvedFormat {
        case .safari:
            let report = try await safariImporter.importFrom(
                url: sourceURL,
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
                url: sourceURL,
                modelContext: modelContext,
                dedupOptions: dedupOptions,
                progress: progress
            )
        case .historyLib:
            return try await historyLibImporter.importFrom(
                url: sourceURL,
                modelContext: modelContext,
                password: password,
                dedupOptions: dedupOptions,
                progress: progress
            )
        }
    }

    private func resolveFormat(url: URL) async throws -> HistoryImportFormatResolved {
        if HistoryLibEncryptedArchive.isEncryptedArchive(url) { return .historyLib }
        if historyLibImporter.looksLikeHistoryLibSource(url) {
            return .historyLib
        }
        // Safari is probed before Chrome: both export a file named History.json,
        // and only a content check tells them apart.
        if await safariImporter.looksLikeSafariHistorySource(url) {
            return .safari
        }
        try Task.checkCancellation()
        if chromeImporter.looksLikeChromeHistorySource(url) {
            return .chrome
        }
        throw HistoryImportError.unrecognizedFormat
    }
}
