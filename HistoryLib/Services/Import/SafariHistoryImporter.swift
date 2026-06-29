import Foundation
import SwiftData

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

        let totalFiles = max(files.count, 1)
        for (fileIndex, file) in files.enumerated() {
            try Task.checkCancellation()
            progress?(HistoryImportProgress(
                fraction: Double(fileIndex) / Double(totalFiles),
                message: String(localized: "Importing records (\(importedRecordCount))...")
            ))
            await Task.yield()
            do {
                let data = try Data(contentsOf: file)
                let export = try JSONDecoder().decode(SafariHistoryExport.self, from: data)

                guard export.metadata.browserName.lowercased() == "safari",
                      export.metadata.dataType.lowercased() == "history" else {
                    failures.append(ImportFileFailure(fileName: file.lastPathComponent, reason: "Not a Safari history export file"))
                    continue
                }

                validFileCount += 1

                let browserName = export.metadata.browserName
                for record in export.history {
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

                    if pendingRecords.count >= insertBatchSize {
                        let flushResult = try ImportDeduplicator.flush(
                            &pendingRecords,
                            modelContext: modelContext,
                            dedupOptions: dedupOptions
                        )
                        importedRecordCount += flushResult.imported
                        skippedRecordCount += flushResult.skipped
                        progress?(HistoryImportProgress(
                            fraction: Double(fileIndex) / Double(totalFiles),
                            message: String(localized: "Importing records (\(importedRecordCount))...")
                        ))
                        try Task.checkCancellation()
                        await Task.yield()
                    }
                }
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
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("HistoryLibImport", isDirectory: true)
        let tempDir = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempDir)
        }

        progress?(HistoryImportProgress(fraction: nil, message: String(localized: "Extracting archive...")))
        await Task.yield()
        do {
            try ImportZipArchive.extractZip(at: zipURL, to: tempDir)
        } catch {
            throw SafariImportError.unzipFailed(message: error.localizedDescription)
        }

        return try await importFromDirectory(tempDir, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
    }
}

private struct SafariHistoryExport: Decodable {
    let metadata: Metadata
    let history: [Record]

    struct Metadata: Decodable {
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
