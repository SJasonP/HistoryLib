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
            return "Only .json files, directories, or .zip files are supported."
        case .unzipFailed(let message):
            return "Failed to unzip archive: \(message)"
        }
    }
}

final class SafariHistoryImporter {
    private let insertBatchSize = 1_000
    private let signatureLookupChunkSize = 800

    func importFrom(
        url: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions = ImportDedupOptions()
    ) throws -> SafariImportReport {
        let fm = FileManager.default
        var isDirectory = ObjCBool(false)
        _ = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            return try importFromDirectory(url, modelContext: modelContext, dedupOptions: dedupOptions)
        }

        let ext = url.pathExtension.lowercased()
        if ext == "json" {
            return try importJSONFiles([url], modelContext: modelContext, dedupOptions: dedupOptions)
        }
        if ext == "zip" {
            return try importFromZip(url, modelContext: modelContext, dedupOptions: dedupOptions)
        }

        throw SafariImportError.unsupportedInputType
    }

    private func importFromDirectory(
        _ directoryURL: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions
    ) throws -> SafariImportReport {
        let jsonFiles = collectJSONFiles(in: directoryURL)
        return try importJSONFiles(jsonFiles, modelContext: modelContext, dedupOptions: dedupOptions)
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

    private struct DedupEntry {
        let signature: String
        let visitedSecond: Int64
        let normalizedURL: String
        let normalizedBrowser: String
    }

    private struct PendingImportRecord {
        let uniqueKey: String
        let dedup: DedupEntry
        let url: String
        let title: String
        let visitedAt: Date
        let visitCount: Int
        let browserName: String
        let sourceFileName: String
        let rawTimeUsec: Int64
        let sourceURL: String?
        let sourceTimeUsec: Int64?
        let destinationURL: String?
        let destinationTimeUsec: Int64?
        let latestVisitWasHTTPGet: Bool?
    }

    private struct FlushResult {
        let imported: Int
        let skipped: Int
    }

    private func importJSONFiles(
        _ files: [URL],
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions
    ) throws -> SafariImportReport {
        var validFileCount = 0
        var importedRecordCount = 0
        var skippedRecordCount = 0
        var failures: [ImportFileFailure] = []
        var pendingRecords: [PendingImportRecord] = []

        for file in files {
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
                    let dedupEntry = Self.makeDedupEntry(
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
                            latestVisitWasHTTPGet: record.latestVisitWasHTTPGet
                        )
                    )

                    if pendingRecords.count >= insertBatchSize {
                        let flushResult = try flushPending(
                            &pendingRecords,
                            modelContext: modelContext,
                            dedupOptions: dedupOptions
                        )
                        importedRecordCount += flushResult.imported
                        skippedRecordCount += flushResult.skipped
                    }
                }
            } catch {
                failures.append(ImportFileFailure(fileName: file.lastPathComponent, reason: error.localizedDescription))
            }
        }

        if !pendingRecords.isEmpty {
            let flushResult = try flushPending(
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

    private func flushPending(
        _ pendingRecords: inout [PendingImportRecord],
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions
    ) throws -> FlushResult {
        guard !pendingRecords.isEmpty else {
            return FlushResult(imported: 0, skipped: 0)
        }

        let tolerance = max(dedupOptions.nearDuplicateToleranceSeconds, 0)
        let strictSignatures = Set(pendingRecords.map(\.uniqueKey))
        let existingStrictSignatures = try fetchExistingSignatures(
            strictSignatures,
            modelContext: modelContext
        )

        let existingNearSignatures: Set<String>
        if dedupOptions.enableNearDuplicateTolerance, tolerance > 0 {
            let nearSignatures = Set(
                pendingRecords.flatMap {
                    Self.nearDuplicateSignatures(for: $0.dedup, toleranceSeconds: tolerance)
                }
            )
            existingNearSignatures = try fetchExistingSignatures(
                nearSignatures,
                modelContext: modelContext
            )
        } else {
            existingNearSignatures = existingStrictSignatures
        }

        var acceptedSignatures: Set<String> = []
        var imported = 0
        var skipped = 0

        for pending in pendingRecords {
            let signature = pending.uniqueKey

            if acceptedSignatures.contains(signature) || existingStrictSignatures.contains(signature) {
                skipped += 1
                continue
            }

            if dedupOptions.enableNearDuplicateTolerance,
               tolerance > 0,
               Self.hasNearDuplicate(
                for: pending.dedup,
                in: acceptedSignatures,
                toleranceSeconds: tolerance
               ) {
                skipped += 1
                continue
            }

            if dedupOptions.enableNearDuplicateTolerance,
               tolerance > 0,
               Self.hasNearDuplicate(
                for: pending.dedup,
                in: existingNearSignatures,
                toleranceSeconds: tolerance
               ) {
                skipped += 1
                continue
            }

            let item = Item(
                uniqueKey: signature,
                url: pending.url,
                title: pending.title,
                visitedAt: pending.visitedAt,
                visitCount: pending.visitCount,
                sourceBrowser: pending.browserName,
                sourceFileName: pending.sourceFileName,
                rawTimeUsec: pending.rawTimeUsec,
                sourceURL: pending.sourceURL,
                sourceTimeUsec: pending.sourceTimeUsec,
                destinationURL: pending.destinationURL,
                destinationTimeUsec: pending.destinationTimeUsec,
                latestVisitWasHTTPGet: pending.latestVisitWasHTTPGet
            )
            modelContext.insert(item)
            acceptedSignatures.insert(signature)
            imported += 1
        }

        if imported > 0 {
            try modelContext.save()
        }

        pendingRecords.removeAll(keepingCapacity: true)
        return FlushResult(imported: imported, skipped: skipped)
    }

    private func fetchExistingSignatures(
        _ signatures: Set<String>,
        modelContext: ModelContext
    ) throws -> Set<String> {
        guard !signatures.isEmpty else {
            return []
        }

        var existing: Set<String> = []
        let signatureArray = Array(signatures)

        for chunk in signatureArray.chunked(into: signatureLookupChunkSize) {
            let chunkArray = Array(chunk)
            let descriptor = FetchDescriptor<Item>(
                predicate: #Predicate<Item> { item in
                    chunkArray.contains(item.uniqueKey)
                }
            )
            let fetched = try modelContext.fetch(descriptor)
            existing.formUnion(fetched.map(\.uniqueKey))
        }

        return existing
    }

    private static func hasNearDuplicate(
        for entry: DedupEntry,
        in signatures: Set<String>,
        toleranceSeconds: Int64
    ) -> Bool {
        for signature in nearDuplicateSignatures(for: entry, toleranceSeconds: toleranceSeconds)
        where signatures.contains(signature) {
            return true
        }
        return false
    }

    private static func nearDuplicateSignatures(
        for entry: DedupEntry,
        toleranceSeconds: Int64
    ) -> [String] {
        guard toleranceSeconds > 0 else {
            return [entry.signature]
        }

        var signatures: [String] = []
        signatures.reserveCapacity(Int((toleranceSeconds * 2) + 1))

        let lowerBound = entry.visitedSecond - toleranceSeconds
        let upperBound = entry.visitedSecond + toleranceSeconds

        for second in lowerBound...upperBound {
            signatures.append(makeSignature(
                normalizedURL: entry.normalizedURL,
                visitedSecond: second,
                normalizedBrowser: entry.normalizedBrowser
            ))
        }

        return signatures
    }

    private static func makeSignature(
        normalizedURL: String,
        visitedSecond: Int64,
        normalizedBrowser: String
    ) -> String {
        "\(normalizedURL)|\(visitedSecond)|\(normalizedBrowser)"
    }

    private static func makeDedupEntry(
        rawURL: String,
        visitedAt: Date,
        browserName: String
    ) -> DedupEntry {
        let normalizedURL = normalizeURLForDedup(rawURL)
        let normalizedBrowser = browserName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let visitedSecond = Int64(visitedAt.timeIntervalSince1970.rounded(.down))

        return DedupEntry(
            signature: makeSignature(
                normalizedURL: normalizedURL,
                visitedSecond: visitedSecond,
                normalizedBrowser: normalizedBrowser
            ),
            visitedSecond: visitedSecond,
            normalizedURL: normalizedURL,
            normalizedBrowser: normalizedBrowser
        )
    }

    private static func normalizeURLForDedup(_ rawURL: String) -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        guard let initialURL = URL(string: trimmed),
              var components = URLComponents(url: initialURL, resolvingAgainstBaseURL: false) else {
            return trimmed.lowercased()
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil

        if let scheme = components.scheme,
           let port = components.port,
           (scheme == "http" && port == 80) || (scheme == "https" && port == 443) {
            components.port = nil
        }

        if components.path.isEmpty {
            components.path = "/"
        } else if components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        return components.string ?? trimmed.lowercased()
    }

    private func importFromZip(
        _ zipURL: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions
    ) throws -> SafariImportReport {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("HistoryLibImport", isDirectory: true)
        let tempDir = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempDir)
        }

        do {
            try ImportZipArchive.extractZip(at: zipURL, to: tempDir)
        } catch {
            throw SafariImportError.unzipFailed(message: error.localizedDescription)
        }

        return try importFromDirectory(tempDir, modelContext: modelContext, dedupOptions: dedupOptions)
    }
}

private extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        guard size > 0 else { return [self[...]] }

        var result: [ArraySlice<Element>] = []
        result.reserveCapacity((count / size) + 1)

        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(self[start..<end])
            start = end
        }

        return result
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

private extension KeyedDecodingContainer {
    func decodeFlexibleInt64IfPresent(forKey key: Key) -> Int64? {
        if let intVal = try? decode(Int64.self, forKey: key) {
            return intVal
        }
        if let intVal = try? decode(Int.self, forKey: key) {
            return Int64(intVal)
        }
        if let strVal = try? decode(String.self, forKey: key),
           let intVal = Int64(strVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intVal
        }
        return nil
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        if let intVal = try? decode(Int.self, forKey: key) {
            return intVal
        }
        if let int64Val = try? decode(Int64.self, forKey: key) {
            return Int(int64Val)
        }
        if let strVal = try? decode(String.self, forKey: key),
           let intVal = Int(strVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intVal
        }
        return nil
    }
}
