import Foundation
import SwiftData
import ZIPFoundation

struct SafariImportReport {
    let scannedJSONFileCount: Int
    let validJSONFileCount: Int
    let importedRecordCount: Int
    let skippedRecordCount: Int
    let failures: [ImportFileFailure]
}

enum SafariImportError: LocalizedError {
    case unsupportedInputType
    case unzipFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedInputType:
            return String(localized: "Only .json files, directories, or .zip files are supported.")
        case .unzipFailed(let message):
            return String(localized: "Failed to unzip archive: \(message)")
        }
    }
}

final class SafariHistoryImporter {
    private let insertBatchSize = 1_000

    func looksLikeSafariHistorySource(_ url: URL) async -> Bool {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        _ = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            for file in collectJSONFiles(in: url) where await isSafariHistoryFile(file) { return true }
            return false
        }

        switch url.pathExtension.lowercased() {
        case "json":
            return await isSafariHistoryFile(url)
        case "zip":
            return await zipContainsSafariHistory(url)
        default:
            return false
        }
    }

    func importFrom(
        url: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions = ImportDedupOptions(),
        progress: HistoryImportProgressHandler? = nil
    ) async throws -> SafariImportReport {
        let fm = FileManager.default
        var isDirectory = ObjCBool(false)
        _ = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            return try await importFromDirectory(url, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
        }

        let ext = url.pathExtension.lowercased()
        if ext == "json" {
            return try await importJSONFiles([url], modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
        }
        if ext == "zip" {
            return try await importFromZip(url, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
        }

        throw SafariImportError.unsupportedInputType
    }

    private func importFromDirectory(
        _ directoryURL: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions,
        progress: HistoryImportProgressHandler?
    ) async throws -> SafariImportReport {
        let jsonFiles = collectJSONFiles(in: directoryURL)
        return try await importJSONFiles(jsonFiles, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
    }

    private func collectJSONFiles(in directoryURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() != "json" {
                continue
            }
            files.append(fileURL)
        }
        return files
    }

    private func isSafariHistoryFile(_ fileURL: URL) async -> Bool {
        let task = Task.detached { try Self.safariMetadata(at: fileURL) }
        return (try? await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }) != nil
    }

    private nonisolated static func safariMetadata(at url: URL) throws -> SafariHistoryExport.Metadata {
        let reader = try HistoryJSONReader(url: url)
        try reader.beginObject()
        var metadata: SafariHistoryExport.Metadata?
        while let key = try reader.nextKey() {
            if key == "metadata" {
                guard metadata == nil else { throw HistoryTransferError.invalidJSON }
                metadata = try JSONDecoder().decode(SafariHistoryExport.Metadata.self, from: reader.value())
            } else {
                try reader.skipValue()
            }
        }
        try reader.finish()
        guard let metadata, metadata.browserName.lowercased() == "safari",
              metadata.dataType.lowercased() == "history" else { throw HistoryImportError.unrecognizedFormat }
        return metadata
    }

    private func zipContainsSafariHistory(_ zipURL: URL) async -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Import", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            HistoryLibSensitiveFiles.applyAttributes(to: directory)
            try await ImportZipArchive.extractInBackground(at: zipURL, to: directory)
            for file in collectJSONFiles(in: directory) where await isSafariHistoryFile(file) { return true }
        } catch { return false }
        return false
    }

    private func importJSONFiles(
        _ files: [URL],
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions,
        progress: HistoryImportProgressHandler?
    ) async throws -> SafariImportReport {
        var validFileCount = 0
        var importedRecordCount = 0
        var skippedRecordCount = 0
        var failures: [ImportFileFailure] = []
        var pendingRecords: [PendingImportRecord] = []
        var pendingBytes = 0

        let totalFiles = max(files.count, 1)
        for (fileIndex, file) in files.enumerated() {
            try Task.checkCancellation()
            progress?(HistoryImportProgress(
                fraction: Double(fileIndex) / Double(totalFiles),
                message: String(localized: "Importing records (\(importedRecordCount))...")
            ))
            await Task.yield()
            do {
                // Probe metadata in a bounded-memory pass, including history-first
                // documents. No writes happen before the envelope is recognized.
                let metadataTask = Task.detached { try Self.safariMetadata(at: file) }
                let metadata = try await withTaskCancellationHandler { try await metadataTask.value } onCancel: { metadataTask.cancel() }
                let browserName = metadata.browserName
                let reader = try HistoryJSONArrayReader(url: file, arrayKey: "history")
                while let recordData = try await reader.nextValue() {
                    guard let record = try? JSONDecoder().decode(SafariHistoryExport.Record.self, from: recordData) else {
                        skippedRecordCount += 1
                        continue
                    }
                    guard let rawURL = record.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !rawURL.isEmpty,
                          let timeUsec = record.timeUsec else {
                        skippedRecordCount += 1
                        continue
                    }

                    let visitedAt = Date(timeIntervalSince1970: TimeInterval(timeUsec) / 1_000_000)
                    let dedupEntry = ImportDedup.makeEntry(
                        rawURL: rawURL,
                        visitedAt: visitedAt,
                        browserName: browserName
                    )

                    pendingRecords.append(
                        PendingImportRecord(
                            uniqueKey: dedupEntry.signature,
                            dedup: dedupEntry,
                            url: rawURL,
                            title: record.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                            visitedAt: visitedAt,
                            visitCount: max(record.visitCount ?? 1, 1),
                            browserName: browserName,
                            sourceFileName: file.lastPathComponent,
                            rawTimeUsec: timeUsec,
                            sourceURL: record.sourceURL,
                            sourceTimeUsec: record.sourceTimeUsec,
                            destinationURL: record.destinationURL,
                            destinationTimeUsec: record.destinationTimeUsec,
                            latestVisitWasHTTPGet: record.latestVisitWasHTTPGet,
                            importedAt: Date()
                        )
                    )

                    pendingBytes += pendingRecords.last!.retainedBytes
                    if pendingRecords.count >= insertBatchSize || pendingBytes >= HistoryTransferLimits.batchBytes {
                        let flushResult = try ImportDeduplicator.flush(
                            &pendingRecords,
                            modelContext: modelContext,
                            dedupOptions: dedupOptions
                        )
                        importedRecordCount += flushResult.imported
                        skippedRecordCount += flushResult.skipped
                        pendingBytes = 0
                        progress?(HistoryImportProgress(
                            fraction: Double(fileIndex) / Double(totalFiles),
                            message: String(localized: "Importing records (\(importedRecordCount))..."),
                            importedRecordCount: importedRecordCount,
                            skippedRecordCount: skippedRecordCount
                        ))
                        try Task.checkCancellation()
                        await Task.yield()
                    }
                }
                validFileCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(ImportFileFailure(fileName: file.lastPathComponent, reason: error.localizedDescription))
            }
        }

        if !pendingRecords.isEmpty {
            let flushResult = try ImportDeduplicator.flush(
                &pendingRecords,
                modelContext: modelContext,
                dedupOptions: dedupOptions
            )
            importedRecordCount += flushResult.imported
            skippedRecordCount += flushResult.skipped
        }

        return SafariImportReport(
            scannedJSONFileCount: files.count,
            validJSONFileCount: validFileCount,
            importedRecordCount: importedRecordCount,
            skippedRecordCount: skippedRecordCount,
            failures: failures
        )
    }

    private func importFromZip(
        _ zipURL: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions,
        progress: HistoryImportProgressHandler?
    ) async throws -> SafariImportReport {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("Import", isDirectory: true)
        let tempDir = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        HistoryLibSensitiveFiles.applyAttributes(to: tempDir)
        defer {
            try? fm.removeItem(at: tempDir)
        }

        progress?(HistoryImportProgress(fraction: nil, message: String(localized: "Extracting archive...")))
        await Task.yield()
        do {
            try await ImportZipArchive.extractInBackground(at: zipURL, to: tempDir)
        } catch {
            throw SafariImportError.unzipFailed(message: error.localizedDescription)
        }

        return try await importFromDirectory(tempDir, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
    }
}

private nonisolated enum SafariHistoryExport {

    struct Metadata: Decodable, Sendable {
        let browserName: String
        let browserVersion: String?
        let dataType: String
        let exportTimeUsec: Int64?
        let schemaVersion: Int?

        private enum CodingKeys: String, CodingKey {
            case browserName = "browser_name"
            case browserVersion = "browser_version"
            case dataType = "data_type"
            case exportTimeUsec = "export_time_usec"
            case schemaVersion = "schema_version"
        }
    }

    struct Record: Decodable {
        let url: String?
        let timeUsec: Int64?
        let visitCount: Int?
        let title: String?
        let sourceURL: String?
        let sourceTimeUsec: Int64?
        let destinationURL: String?
        let destinationTimeUsec: Int64?
        let latestVisitWasHTTPGet: Bool?

        private enum CodingKeys: String, CodingKey {
            case url
            case timeUsec = "time_usec"
            case visitCount = "visit_count"
            case title
            case sourceURL = "source_url"
            case sourceTimeUsec = "source_time_usec"
            case destinationURL = "destination_url"
            case destinationTimeUsec = "destination_time_usec"
            case latestVisitWasHTTPGet = "latest_visit_was_http_get"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            timeUsec = container.decodeFlexibleInt64IfPresent(forKey: .timeUsec)
            visitCount = container.decodeFlexibleIntIfPresent(forKey: .visitCount)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
            sourceTimeUsec = container.decodeFlexibleInt64IfPresent(forKey: .sourceTimeUsec)
            destinationURL = try container.decodeIfPresent(String.self, forKey: .destinationURL)
            destinationTimeUsec = container.decodeFlexibleInt64IfPresent(forKey: .destinationTimeUsec)
            latestVisitWasHTTPGet = try container.decodeIfPresent(Bool.self, forKey: .latestVisitWasHTTPGet)
        }
    }
}
