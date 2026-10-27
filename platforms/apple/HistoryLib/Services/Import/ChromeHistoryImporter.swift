import Foundation
import SwiftData
import ZIPFoundation

// Importer for Chrome history exported through Google Takeout.
//
// Chrome has no built-in history export; Google Takeout is the only official
// route. It produces `Takeout/Chrome/History.json` (older exports name it
// `BrowserHistory.json`), usually delivered inside a .zip:
//
//     { "Browser History": [ { "url": …, "title": …, "time_usec": … }, … ] }
//
// `time_usec` is microseconds since the Unix epoch — the same unit Safari's
// export uses — so records map onto the shared import pipeline with no epoch
// conversion. (Chrome's *local* `History` SQLite database instead uses the 1601
// WebKit epoch; that format is deliberately not supported here.)
//
// Takeout carries no visit_count, no redirect chain, and no metadata block, so
// those fields are left at their defaults.

enum ChromeImportError: LocalizedError {
    case unsupportedInputType
    case unzipFailed(message: String)

    var errorDescription: String? {
        switch self {
        // These reuse the Safari importer's exact wording on purpose: the String
        // Catalog keys off the literal, so the existing translations apply.
        case .unsupportedInputType:
            return String(localized: "Only .json files, directories, or .zip files are supported.")
        case .unzipFailed(let message):
            return String(localized: "Failed to unzip archive: \(message)")
        }
    }
}

final class ChromeHistoryImporter {
    private let insertBatchSize = 1_000

    /// Bytes inspected when sniffing a file. Takeout history files are commonly
    /// hundreds of megabytes, so detection must never decode the whole document
    /// just to answer a Bool.
    static let sniffByteLimit = 64 * 1024
    private static let historyKeyToken = Data("\"Browser History\"".utf8)

    func looksLikeChromeHistorySource(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        _ = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            return collectJSONFiles(in: url).contains(where: fileLooksLikeChromeHistory)
        }

        switch url.pathExtension.lowercased() {
        case "json":
            return fileLooksLikeChromeHistory(url)
        case "zip":
            return zipContainsChromeHistory(url)
        default:
            return false
        }
    }

    func importFrom(
        url: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions = ImportDedupOptions(),
        progress: HistoryImportProgressHandler? = nil
    ) async throws -> HistoryImportReport {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        _ = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            return try await importFromDirectory(url, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
        }

        let ext = url.pathExtension.lowercased()
        if ext == "json" {
            return try await importJSONFiles(
                [url],
                scannedFileCount: 1,
                modelContext: modelContext,
                dedupOptions: dedupOptions,
                progress: progress
            )
        }
        if ext == "zip" {
            return try await importFromZip(url, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
        }

        throw ChromeImportError.unsupportedInputType
    }

    private func importFromDirectory(
        _ directoryURL: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions,
        progress: HistoryImportProgressHandler?
    ) async throws -> HistoryImportReport {
        // A Takeout folder holds unrelated JSON siblings (Autofill, SearchEngines,
        // …). Only history files are imported; the rest are skipped quietly rather
        // than reported as failures.
        let jsonFiles = collectJSONFiles(in: directoryURL)
        let historyFiles = jsonFiles.filter(fileLooksLikeChromeHistory)
        return try await importJSONFiles(
            historyFiles,
            scannedFileCount: jsonFiles.count,
            modelContext: modelContext,
            dedupOptions: dedupOptions,
            progress: progress
        )
    }

    private func importFromZip(
        _ zipURL: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions,
        progress: HistoryImportProgressHandler?
    ) async throws -> HistoryImportReport {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("Import", isDirectory: true)
        let tempDir = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        HistoryLibSensitiveFiles.applyAttributes(to: tempDir)
        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        progress?(HistoryImportProgress(fraction: nil, message: String(localized: "Extracting archive...")))
        await Task.yield()
        do {
            try await ImportZipArchive.extractInBackground(at: zipURL, to: tempDir)
        } catch {
            throw ChromeImportError.unzipFailed(message: error.localizedDescription)
        }

        return try await importFromDirectory(tempDir, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
    }

    private func importJSONFiles(
        _ files: [URL],
        scannedFileCount: Int,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions,
        progress: HistoryImportProgressHandler?
    ) async throws -> HistoryImportReport {
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
                let browserName = inferBrowserName(from: file)
                let malformedRecordCount = try await ChromeTakeoutStreamParser().parse(url: file) { record in
                    guard let rawURL = record.url?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !rawURL.isEmpty,
                          let timeUsec = record.timeUsec else {
                        skippedRecordCount += 1
                        return
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
                            // Takeout has no visit_count: each entry is one visit.
                            visitCount: 1,
                            browserName: browserName,
                            sourceFileName: file.lastPathComponent,
                            // Already Unix-epoch microseconds, which is what the
                            // .hlz exporter writes back out verbatim.
                            rawTimeUsec: timeUsec,
                            sourceURL: nil,
                            sourceTimeUsec: nil,
                            destinationURL: nil,
                            destinationTimeUsec: nil,
                            latestVisitWasHTTPGet: nil,
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
                    }
                }
                skippedRecordCount += malformedRecordCount
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

        return HistoryImportReport(
            format: .chrome,
            scannedFileCount: scannedFileCount,
            validFileCount: validFileCount,
            importedRecordCount: importedRecordCount,
            skippedRecordCount: skippedRecordCount,
            failures: failures
        )
    }

    /// Takeout itself only ever comes from Chrome, but the file may have been
    /// filed away under a Chromium-family browser's name. Fall back to Chrome.
    private func inferBrowserName(from fileURL: URL) -> String {
        let knownBrowsers: [(needle: String, name: String)] = [
            ("microsoft edge", "Microsoft Edge"),
            ("bravesoftware", "Brave"),
            ("brave", "Brave"),
            ("vivaldi", "Vivaldi"),
            ("opera", "Opera"),
            ("chromium", "Chrome"),
            ("chrome", "Chrome")
        ]

        for component in fileURL.deletingLastPathComponent().pathComponents.reversed() {
            let lowercased = component.lowercased()
            for browser in knownBrowsers where lowercased.contains(browser.needle) {
                return browser.name
            }
        }
        return "Chrome"
    }

    private func collectJSONFiles(in directoryURL: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
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

    private func fileLooksLikeChromeHistory(_ fileURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: Self.sniffByteLimit) else { return false }
        return Self.dataLooksLikeChromeHistory(prefix)
    }

    private func zipContainsChromeHistory(_ zipURL: URL) -> Bool {
        guard let archive = try? Archive(url: zipURL, accessMode: .read, pathEncoding: nil) else {
            return false
        }

        for entry in archive where entry.type == .file && entry.path.lowercased().hasSuffix(".json") {
            if entryPrefixLooksLikeChromeHistory(entry, in: archive) {
                return true
            }
        }
        return false
    }

    private func entryPrefixLooksLikeChromeHistory(_ entry: Entry, in archive: Archive) -> Bool {
        struct EnoughBytesRead: Error {}

        var buffer = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                buffer.append(chunk)
                // Stop as soon as the prefix is long enough: a Takeout archive can
                // be many gigabytes, and detection only needs the head.
                if buffer.count >= Self.sniffByteLimit {
                    throw EnoughBytesRead()
                }
            }
        } catch is EnoughBytesRead {
            // Expected: the prefix was collected.
        } catch {
            return false
        }
        return Self.dataLooksLikeChromeHistory(buffer)
    }

    /// True when `"Browser History"` appears as a JSON *key* (i.e. followed by a
    /// colon). Checking for the colon matters: a record whose title happens to be
    /// "Browser History" would otherwise match.
    private static func dataLooksLikeChromeHistory(_ data: Data) -> Bool {
        var searchStart = data.startIndex
        while let tokenRange = data.range(of: historyKeyToken, in: searchStart..<data.endIndex) {
            var index = tokenRange.upperBound
            while index < data.endIndex, isJSONWhitespace(data[index]) {
                index = data.index(after: index)
            }
            if index < data.endIndex, data[index] == UInt8(ascii: ":") {
                return true
            }
            searchStart = tokenRange.upperBound
        }
        return false
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}
