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
            return "HistoryLib import supports .hlz, .zip, or a directory."
        case .missingManifest:
            return "No HistoryLib manifest.json file was found."
        case .invalidManifest:
            return "Invalid HistoryLib manifest format."
        case .unsupportedFormatVersion(let version):
            return "Unsupported HistoryLib format version: \(version)."
        case .missingChunkIndex:
            return "Missing required chunk index for HistoryLib archive."
        case .invalidChunkIndex:
            return "Invalid chunks index in HistoryLib archive."
        case .manifestCountMismatch(let field, let expected, let actual):
            return "Manifest validation failed for \(field): expected \(expected), actual \(actual)."
        case .checksumMismatch(let chunkPath):
            return "Chunk checksum validation failed: \(chunkPath)"
        case .invalidChunkRecord(let chunkPath, let line):
            return "Invalid chunk record at \(chunkPath): line \(line)."
        case .noChunkFiles:
            return "No HistoryLib chunk files were found."
        case .invalidPath(let path):
            return "Invalid archive path: \(path)"
        }
    }
}

final class HistoryLibArchiveImporter {
    private let insertBatchSize = 1_000
    private let signatureLookupChunkSize = 800
    private let decoder = JSONDecoder()

    func importFrom(
        url: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions = ImportDedupOptions()
    ) throws -> HistoryImportReport {
        let fm = FileManager.default
        var isDirectory = ObjCBool(false)
        _ = fm.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            return try importFromDirectory(url, modelContext: modelContext, dedupOptions: dedupOptions)
        }

        let ext = url.pathExtension.lowercased()
        if ext == "hlz" || ext == "zip" {
            return try importFromZipFile(url, modelContext: modelContext, dedupOptions: dedupOptions)
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
        dedupOptions: ImportDedupOptions
    ) throws -> HistoryImportReport {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("HistoryLibImport", isDirectory: true)
        let tempDir = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempDir)
        }

        try ImportZipArchive.extractZip(at: zipURL, to: tempDir)
        return try importFromDirectory(tempDir, modelContext: modelContext, dedupOptions: dedupOptions)
    }

    private func importFromDirectory(
        _ directoryURL: URL,
        modelContext: ModelContext,
        dedupOptions: ImportDedupOptions
    ) throws -> HistoryImportReport {
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
        let chunkEntries = try validatedChunkEntries(manifest: manifest, archiveRoot: archiveRoot)
        var importedRecordCount = 0
        var skippedRecordCount = 0
        var pendingRecords: [PendingImportRecord] = []

        for entry in chunkEntries {
            let chunkURL = try safeArchiveURL(forRelativePath: entry.path, archiveRoot: archiveRoot)
            try appendChunkRecords(
                from: chunkURL,
                chunkPath: entry.path,
                pendingRecords: &pendingRecords
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

        if !pendingRecords.isEmpty {
            let flushResult = try flushPending(
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
        guard !data.isEmpty else {
            throw HistoryLibImportError.invalidChunkRecord(chunkPath: chunkPath, line: 1)
        }

        let lines = String(decoding: data, as: UTF8.self)
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
        for (lineIndex, line) in lines.enumerated() {
            let lineData = Data(line.utf8)

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

            let dedupEntry = Self.makeDedupEntry(
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
        archiveRoot: URL
    ) throws -> [HLChunkIndexEntryEnvelope] {
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

            let actualRecordCount = String(decoding: chunkData, as: UTF8.self)
                .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
                .count
            if actualRecordCount != entry.recordCount {
                throw HistoryLibImportError.manifestCountMismatch(
                    field: "record_count(\(entry.path))",
                    expected: entry.recordCount,
                    actual: actualRecordCount
                )
            }

            try validateChunkRecordSchema(chunkData, chunkPath: entry.path)
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

    private func validateChunkRecordSchema(_ chunkData: Data, chunkPath: String) throws {
        let lines = String(decoding: chunkData, as: UTF8.self)
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)

        for (lineIndex, line) in lines.enumerated() {
            let lineData = Data(line.utf8)
            guard let record = try? decoder.decode(HLChunkRecord.self, from: lineData),
                  let rawURLValue = record.u?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawURLValue.isEmpty,
                  record.ts != nil else {
                throw HistoryLibImportError.invalidChunkRecord(chunkPath: chunkPath, line: lineIndex + 1)
            }
        }
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
        let importedAt: Date
    }

    private struct FlushResult {
        let imported: Int
        let skipped: Int
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
                latestVisitWasHTTPGet: pending.latestVisitWasHTTPGet,
                importedAt: pending.importedAt
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
        if let intVal = try? decode(Int64.self, forKey: key) {
            return Int(intVal)
        }
        if let strVal = try? decode(String.self, forKey: key),
           let intVal = Int(strVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intVal
        }
        return nil
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
