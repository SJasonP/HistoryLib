import CryptoKit
import Foundation
import SwiftData
import ZIPFoundation

enum HistoryLibImportError: LocalizedError {
    case unsupportedInputType
    case missingManifest
    case invalidManifest
    case unsupportedFormatVersion(Int)
    case missingChunkIndex
    case invalidChunkIndex
    case manifestCountMismatch(field: String, expected: Int, actual: Int)
    case checksumMismatch(chunkPath: String)
    case invalidChunkRecord(chunkPath: String, line: Int)
    case noChunkFiles
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedInputType:
            return String(localized: "HistoryLib import supports .hlz, .zip, or a directory.")
        case .missingManifest:
            return String(localized: "No HistoryLib manifest.json file was found.")
        case .invalidManifest:
            return String(localized: "Invalid HistoryLib manifest format.")
        case .unsupportedFormatVersion(let version):
            return String(localized: "Unsupported HistoryLib format version: \(version).")
        case .missingChunkIndex:
            return String(localized: "Missing required chunk index for HistoryLib archive.")
        case .invalidChunkIndex:
            return String(localized: "Invalid chunks index in HistoryLib archive.")
        case .manifestCountMismatch(let field, let expected, let actual):
            return String(localized: "Manifest validation failed for \(field): expected \(expected), actual \(actual).")
        case .checksumMismatch(let chunkPath):
            return String(localized: "Chunk checksum validation failed: \(chunkPath)")
        case .invalidChunkRecord(let chunkPath, let line):
            return String(localized: "Invalid chunk record at \(chunkPath): line \(line).")
        case .noChunkFiles:
            return String(localized: "No HistoryLib chunk files were found.")
        case .invalidPath(let path):
            return String(localized: "Invalid archive path: \(path)")
        }
    }
}

final class HistoryLibArchiveImporter {
    private let insertBatchSize = 1_000
    private let decoder = JSONDecoder()

    func importFrom(
        url: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions = ImportDedupOptions(),
        progress: HistoryImportProgressHandler? = nil
    ) async throws -> HistoryImportReport {
        let fm = FileManager.default
        var isDirectory = ObjCBool(false)
        _ = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            return try await importFromDirectory(url, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
        }

        let ext = url.pathExtension.lowercased()
        if ext == "hlz" || ext == "zip" {
            return try await importFromZipFile(url, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
        }

        throw HistoryLibImportError.unsupportedInputType
    }

    func looksLikeHistoryLibSource(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDirectory = ObjCBool(false)
        _ = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            return findHistoryLibManifest(in: url) != nil
        }

        let ext = url.pathExtension.lowercased()
        if ext == "hlz" {
            return true
        }
        if ext == "zip" {
            return zipContainsHistoryLibManifest(url)
        }

        return false
    }

    private func importFromZipFile(
        _ zipURL: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions,
        progress: HistoryImportProgressHandler?
    ) async throws -> HistoryImportReport {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("HistoryLibImport", isDirectory: true)
        let tempDir = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempDir)
        }

        progress?(HistoryImportProgress(fraction: nil, message: String(localized: "Extracting archive...")))
        await Task.yield()
        try ImportZipArchive.extractZip(at: zipURL, to: tempDir)
        return try await importFromDirectory(tempDir, modelContext: modelContext, dedupOptions: dedupOptions, progress: progress)
    }

    private func importFromDirectory(
        _ directoryURL: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions,
        progress: HistoryImportProgressHandler?
    ) async throws -> HistoryImportReport {
        guard let (manifestURL, manifest) = findHistoryLibManifest(in: directoryURL) else {
            throw HistoryLibImportError.missingManifest
        }
        guard manifest.format.lowercased() == "historylib" else {
            throw HistoryLibImportError.invalidManifest
        }
        guard manifest.formatVersion == 1 else {
            throw HistoryLibImportError.unsupportedFormatVersion(manifest.formatVersion)
        }

        let archiveRoot = manifestURL.deletingLastPathComponent()

        // Validate the whole archive (structure, checksums, counts) before
        // trusting any chunk, so a corrupt archive imports nothing. This pass
        // does not decode records — it only hashes bytes and counts lines.
        let chunkEntries = try await validatedChunkEntries(manifest: manifest, archiveRoot: archiveRoot, progress: progress)

        let totalRecords = max(chunkEntries.reduce(0) { $0 + $1.recordCount }, 1)
        var importedRecordCount = 0
        var skippedRecordCount = 0
        var processedRecords = 0
        var pendingRecords: [PendingImportRecord] = []

        // Import pass: each chunk is read once and each record decoded once.
        for entry in chunkEntries {
            try Task.checkCancellation()
            let chunkURL = try safeArchiveURL(forRelativePath: entry.path, archiveRoot: archiveRoot)
            try appendChunkRecords(
                from: chunkURL,
                chunkPath: entry.path,
                pendingRecords: &pendingRecords
            )
            processedRecords += entry.recordCount

            if pendingRecords.count >= insertBatchSize {
                let flushResult = try ImportDeduplicator.flush(
                    &pendingRecords,
                    modelContext: modelContext,
                    dedupOptions: dedupOptions
                )
                importedRecordCount += flushResult.imported
                skippedRecordCount += flushResult.skipped
            }

            progress?(HistoryImportProgress(
                fraction: 0.2 + 0.8 * (Double(processedRecords) / Double(totalRecords)),
                message: String(localized: "Importing records (\(processedRecords)/\(totalRecords))...")
            ))
            await Task.yield()
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
            format: .historyLib,
            scannedFileCount: chunkEntries.count,
            validFileCount: chunkEntries.count,
            importedRecordCount: importedRecordCount,
            skippedRecordCount: skippedRecordCount,
            failures: []
        )
    }

    private func appendChunkRecords(
        from chunkURL: URL,
        chunkPath: String,
        pendingRecords: inout [PendingImportRecord]
    ) throws {
        let data = try Data(contentsOf: chunkURL, options: [.mappedIfSafe])

        // Split on the raw newline byte so we never materialize the whole chunk
        // as one Swift String. Each line is decoded exactly once.
        for (lineIndex, lineSlice) in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true).enumerated() {
            var lineData = Data(lineSlice)
            if lineData.last == UInt8(ascii: "\r") {
                lineData.removeLast()
            }
            if lineData.isEmpty {
                continue
            }

            guard let record = try? decoder.decode(HLChunkRecord.self, from: lineData),
                  let rawURLValue = record.u?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                  !rawURLValue.isEmpty,
                  let timeUsec = record.ts else {
                throw HistoryLibImportError.invalidChunkRecord(chunkPath: chunkPath, line: lineIndex + 1)
            }

            let visitedAt = Date(timeIntervalSince1970: TimeInterval(timeUsec) / 1_000_000)
            let browserName: String
            if let source = record.sb?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !source.isEmpty {
                browserName = source
            } else {
                browserName = "Safari"
            }

            let dedupEntry = ImportDedup.makeEntry(
                rawURL: rawURLValue,
                visitedAt: visitedAt,
                browserName: browserName
            )
            let importedUniqueKey = record.uk?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let uniqueKey = (importedUniqueKey?.isEmpty == false) ? importedUniqueKey! : dedupEntry.signature

            let importedAt: Date
            if let importedAtUsec = record.ia, importedAtUsec > 0 {
                importedAt = Date(timeIntervalSince1970: TimeInterval(importedAtUsec) / 1_000_000)
            } else {
                importedAt = Date()
            }

            pendingRecords.append(
                PendingImportRecord(
                    uniqueKey: uniqueKey,
                    dedup: dedupEntry,
                    url: rawURLValue,
                    title: record.t?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? "",
                    visitedAt: visitedAt,
                    visitCount: max(record.vc ?? 1, 1),
                    browserName: browserName,
                    sourceFileName: record.sf?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? chunkURL.lastPathComponent,
                    rawTimeUsec: (record.rt ?? 0) > 0 ? (record.rt ?? 0) : timeUsec,
                    sourceURL: record.su,
                    sourceTimeUsec: record.st,
                    destinationURL: record.du,
                    destinationTimeUsec: record.dt,
                    latestVisitWasHTTPGet: record.hg,
                    importedAt: importedAt
                )
            )
        }
    }

    private func validatedChunkEntries(
        manifest: HLManifestEnvelope,
        archiveRoot: URL,
        progress: HistoryImportProgressHandler?
    ) async throws -> [HLChunkIndexEntryEnvelope] {
        guard let chunksIndexPath = manifest.indexes?.chunks,
              !chunksIndexPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HistoryLibImportError.missingChunkIndex
        }

        let indexURL = try safeArchiveURL(forRelativePath: chunksIndexPath, archiveRoot: archiveRoot)
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw HistoryLibImportError.missingChunkIndex
        }

        let indexData = try Data(contentsOf: indexURL)
        let parsedEntries = try decoder.decode([HLChunkIndexEntryEnvelope].self, from: indexData)
        if parsedEntries.isEmpty {
            if manifest.recordCount == 0, manifest.chunkCount == 0 {
                return []
            }
            throw HistoryLibImportError.noChunkFiles
        }

        let sortedEntries = parsedEntries.sorted { lhs, rhs in
            if lhs.id == rhs.id {
                return lhs.path < rhs.path
            }
            return lhs.id < rhs.id
        }

        var seenChunkPaths: Set<String> = []
        for (index, entry) in sortedEntries.enumerated() {
            try Task.checkCancellation()
            progress?(HistoryImportProgress(
                fraction: 0.2 * (Double(index) / Double(sortedEntries.count)),
                message: String(localized: "Validating archive...")
            ))
            await Task.yield()
            guard entry.id == index + 1 else {
                throw HistoryLibImportError.invalidChunkIndex
            }
            guard entry.recordCount > 0 else {
                throw HistoryLibImportError.invalidChunkIndex
            }
            guard !entry.sha256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HistoryLibImportError.invalidChunkIndex
            }
            guard seenChunkPaths.insert(entry.path).inserted else {
                throw HistoryLibImportError.invalidChunkIndex
            }

            let chunkURL = try safeArchiveURL(forRelativePath: entry.path, archiveRoot: archiveRoot)
            guard FileManager.default.fileExists(atPath: chunkURL.path) else {
                throw HistoryLibImportError.invalidPath(entry.path)
            }

            let chunkData = try Data(contentsOf: chunkURL, options: [.mappedIfSafe])
            let digest = SHA256.hash(data: chunkData)
            let sha256 = digest.map { String(format: "%02x", $0) }.joined()
            guard sha256.lowercased() == entry.sha256.lowercased() else {
                throw HistoryLibImportError.checksumMismatch(chunkPath: entry.path)
            }

            let actualRecordCount = newlineDelimitedLineCount(chunkData)
            if actualRecordCount != entry.recordCount {
                throw HistoryLibImportError.manifestCountMismatch(
                    field: "record_count(\(entry.path))",
                    expected: entry.recordCount,
                    actual: actualRecordCount
                )
            }
        }

        if manifest.chunkCount != sortedEntries.count {
            throw HistoryLibImportError.manifestCountMismatch(
                field: "chunk_count",
                expected: manifest.chunkCount,
                actual: sortedEntries.count
            )
        }

        let indexedRecordCount = sortedEntries.reduce(0) { $0 + $1.recordCount }
        if manifest.recordCount != indexedRecordCount {
            throw HistoryLibImportError.manifestCountMismatch(
                field: "record_count",
                expected: manifest.recordCount,
                actual: indexedRecordCount
            )
        }

        return sortedEntries
    }

    private func newlineDelimitedLineCount(_ data: Data) -> Int {
        let newline = UInt8(ascii: "\n")
        let carriage = UInt8(ascii: "\r")
        var count = 0
        var lineHasContent = false
        for byte in data {
            if byte == newline {
                if lineHasContent {
                    count += 1
                }
                lineHasContent = false
            } else if byte != carriage {
                lineHasContent = true
            }
        }
        if lineHasContent {
            count += 1
        }
        return count
    }

    private func findHistoryLibManifest(in directoryURL: URL) -> (URL, HLManifestEnvelope)? {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var bestResult: (url: URL, manifest: HLManifestEnvelope)?
        var bestDepth: Int = .max

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.lowercased() == "manifest.json" else {
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            guard let data = try? Data(contentsOf: fileURL),
                  let manifest = try? decoder.decode(HLManifestEnvelope.self, from: data),
                  manifest.format.lowercased() == "historylib" else {
                continue
            }

            let depth = fileURL.pathComponents.count
            if depth < bestDepth {
                bestDepth = depth
                bestResult = (fileURL, manifest)
            }
        }

        if let bestResult {
            return (bestResult.url, bestResult.manifest)
        }
        return nil
    }

    private func zipContainsHistoryLibManifest(_ zipURL: URL) -> Bool {
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read, pathEncoding: nil)
        } catch {
            return false
        }

        for entry in archive where entry.type != .directory {
            let path = entry.path.lowercased()
            guard path == "manifest.json" || path.hasSuffix("/manifest.json") else {
                continue
            }

            var data = Data()
            do {
                _ = try archive.extract(entry) { chunk in
                    data.append(chunk)
                }
                let manifest = try decoder.decode(HLManifestEnvelope.self, from: data)
                if manifest.format.lowercased() == "historylib" {
                    return true
                }
            } catch {
                continue
            }
        }

        return false
    }

    private func safeArchiveURL(forRelativePath relativePath: String, archiveRoot: URL) throws -> URL {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw HistoryLibImportError.invalidPath(relativePath)
        }

        let normalizedPath = trimmedPath.replacingOccurrences(of: "\\", with: "/")
        let unsafeURL = archiveRoot.appendingPathComponent(normalizedPath)
        let standardizedURL = unsafeURL.standardizedFileURL
        let rootPath = archiveRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let targetURL = standardizedURL.resolvingSymlinksInPath()
        let targetPath = targetURL.path
        let isInsideRoot = targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
        guard isInsideRoot else {
            throw HistoryLibImportError.invalidPath(relativePath)
        }
        return targetURL
    }
}

private struct HLManifestEnvelope: Decodable {
    let format: String
    let formatVersion: Int
    let recordCount: Int
    let chunkCount: Int
    let indexes: HLManifestIndexesEnvelope?

    private enum CodingKeys: String, CodingKey {
        case format
        case formatVersion = "format_version"
        case recordCount = "record_count"
        case chunkCount = "chunk_count"
        case indexes
    }
}

private struct HLManifestIndexesEnvelope: Decodable {
    let chunks: String?
}

private struct HLChunkIndexEntryEnvelope: Decodable {
    let id: Int
    let path: String
    let recordCount: Int
    let minTs: Int64?
    let maxTs: Int64?
    let sha256: String

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case recordCount = "record_count"
        case minTs = "min_ts"
        case maxTs = "max_ts"
        case sha256
    }
}

private struct HLChunkRecord: Decodable {
    let u: String?
    let ts: Int64?
    let t: String?
    let vc: Int?
    let uk: String?
    let sb: String?
    let ia: Int64?
    let rt: Int64?
    let sf: String?
    let su: String?
    let st: Int64?
    let du: String?
    let dt: Int64?
    let hg: Bool?

    private enum CodingKeys: String, CodingKey {
        case u
        case ts
        case t
        case vc
        case uk
        case sb
        case ia
        case rt
        case sf
        case su
        case st
        case du
        case dt
        case hg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        u = try container.decodeIfPresent(String.self, forKey: .u)
        ts = container.decodeFlexibleInt64IfPresent(forKey: .ts)
        t = try container.decodeIfPresent(String.self, forKey: .t)
        vc = container.decodeFlexibleIntIfPresent(forKey: .vc)
        uk = try container.decodeIfPresent(String.self, forKey: .uk)
        sb = try container.decodeIfPresent(String.self, forKey: .sb)
        ia = container.decodeFlexibleInt64IfPresent(forKey: .ia)
        rt = container.decodeFlexibleInt64IfPresent(forKey: .rt)
        sf = try container.decodeIfPresent(String.self, forKey: .sf)
        su = try container.decodeIfPresent(String.self, forKey: .su)
        st = container.decodeFlexibleInt64IfPresent(forKey: .st)
        du = try container.decodeIfPresent(String.self, forKey: .du)
        dt = container.decodeFlexibleInt64IfPresent(forKey: .dt)
        hg = try container.decodeIfPresent(Bool.self, forKey: .hg)
    }
}
