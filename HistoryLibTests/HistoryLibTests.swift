import CryptoKit
import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
import ZIPFoundation
@testable import History_Lib

@Suite("History Data Path Tests")
@MainActor
struct HistoryLibTests {
    @Test("Safari import applies strict dedup for exact duplicates")
    func safariImportStrictDedup() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let sharedTimeUsec: Int64 = 1_710_000_000_000_000
        let jsonURL = try fixture.writeSafariExportJSON(
            records: [
                .init(url: "https://example.com/a", timeUsec: sharedTimeUsec, title: "A"),
                .init(url: "https://example.com/a", timeUsec: sharedTimeUsec, title: "A duplicate"),
                .init(url: "https://example.com/b", timeUsec: sharedTimeUsec + 5_000_000, title: "B")
            ]
        )

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: jsonURL,
            modelContext: fixture.context,
            preferredFormat: .safari,
            dedupOptions: ImportDedupOptions(enableNearDuplicateTolerance: false, nearDuplicateToleranceSeconds: 0)
        )

        #expect(report.importedRecordCount == 2)
        #expect(report.skippedRecordCount == 1)
        #expect(try fixture.recordCount() == 2)
    }

    @Test("Safari import near-duplicate tolerance is enabled by default")
    func safariImportNearDuplicateDefaultEnabled() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let firstURL = try fixture.writeSafariExportJSON(
            records: [
                .init(url: "https://example.com/near", timeUsec: 1_710_000_000_000_000, title: "Near 1")
            ]
        )
        let secondURL = try fixture.writeSafariExportJSON(
            records: [
                .init(url: "https://example.com/near", timeUsec: 1_710_000_001_000_000, title: "Near 2")
            ]
        )

        let importer = HistoryImporter()
        _ = try await importer.importFrom(url: firstURL, modelContext: fixture.context, preferredFormat: .safari)
        let secondReport = try await importer.importFrom(url: secondURL, modelContext: fixture.context, preferredFormat: .safari)

        #expect(secondReport.importedRecordCount == 0)
        #expect(secondReport.skippedRecordCount == 1)
        #expect(try fixture.recordCount() == 1)
    }

    @Test("HistoryLib export can be imported back without record loss")
    func historyLibRoundTripExportImport() async throws {
        let source = try TestFixture()
        defer { source.cleanup() }

        try source.insertItem(
            url: "https://alpha.example/path",
            title: "Alpha",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "alpha-key"
        )
        try source.insertItem(
            url: "https://beta.example/path",
            title: "Beta",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_100),
            browser: "Safari",
            uniqueKey: "beta-key"
        )
        try source.insertItem(
            url: "https://gamma.example/path",
            title: "Gamma",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_200),
            browser: "Safari",
            uniqueKey: "gamma-key"
        )

        let exporter = HistoryExporter()
        let prepared = try await exporter.prepareExportFile(
            modelContext: source.context,
            format: .historyLib,
            split: .single
        )
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectoryURL) }

        #expect(prepared.fileURL.pathExtension.lowercased() == "hlz")
        #expect(FileManager.default.fileExists(atPath: prepared.fileURL.path))

        let target = try TestFixture()
        defer { target.cleanup() }

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: prepared.fileURL,
            modelContext: target.context,
            preferredFormat: .historyLib
        )

        #expect(report.format == .historyLib)
        #expect(report.importedRecordCount == 3)
        #expect(try target.recordCount() == 3)
    }

    @Test("Safari single-file export is packaged as zip and can be imported back")
    func safariSingleZipRoundTripExportImport() async throws {
        let source = try TestFixture()
        defer { source.cleanup() }

        try source.insertItem(
            url: "https://single.example",
            title: "Single",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "single"
        )

        let exporter = HistoryExporter()
        let prepared = try await exporter.prepareExportFile(
            modelContext: source.context,
            format: .safari,
            split: .single
        )
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectoryURL) }

        #expect(prepared.fileURL.pathExtension.lowercased() == "zip")
        #expect(prepared.contentType == .zip)
        #expect(FileManager.default.fileExists(atPath: prepared.fileURL.path))

        let target = try TestFixture()
        defer { target.cleanup() }

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: prepared.fileURL,
            modelContext: target.context,
            preferredFormat: .safari
        )

        #expect(report.importedRecordCount == 1)
        #expect(try target.recordCount() == 1)
    }

    @Test("Safari day-split zip export can be imported back")
    func safariZipRoundTripExportImport() async throws {
        let source = try TestFixture()
        defer { source.cleanup() }

        try source.insertItem(
            url: "https://one.example",
            title: "One",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "one"
        )
        try source.insertItem(
            url: "https://two.example",
            title: "Two",
            visitedAt: Date(timeIntervalSince1970: 1_710_086_400),
            browser: "Safari",
            uniqueKey: "two"
        )

        let exporter = HistoryExporter()
        let prepared = try await exporter.prepareExportFile(
            modelContext: source.context,
            format: .safari,
            split: .day
        )
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectoryURL) }

        #expect(prepared.fileURL.pathExtension.lowercased() == "zip")
        #expect(FileManager.default.fileExists(atPath: prepared.fileURL.path))

        let target = try TestFixture()
        defer { target.cleanup() }

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: prepared.fileURL,
            modelContext: target.context,
            preferredFormat: .safari
        )

        #expect(report.importedRecordCount == 2)
        #expect(try target.recordCount() == 2)
    }

    @Test("Background duplicate cleaner removes near duplicates")
    func duplicateCleanerRemovesNearDuplicates() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        try fixture.insertItem(
            url: "https://cleaner.example",
            title: "A",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "a"
        )
        try fixture.insertItem(
            url: "https://cleaner.example",
            title: "B",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_001),
            browser: "Safari",
            uniqueKey: "b"
        )
        try fixture.insertItem(
            url: "https://cleaner.example",
            title: "C",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_003),
            browser: "Safari",
            uniqueKey: "c"
        )

        let cleaner = HistoryDuplicateCleaner()
        let report = try await cleaner.deduplicate(
            modelContainer: fixture.container,
            dedupOptions: ImportDedupOptions(enableNearDuplicateTolerance: true, nearDuplicateToleranceSeconds: 1)
        )

        #expect(report.removedCount == 1)
        #expect(try fixture.recordCount() == 2)
    }

    @Test("Import merges visit counts for exact duplicates instead of discarding them")
    func importMergesVisitCounts() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let sharedTimeUsec: Int64 = 1_710_000_000_000_000
        let jsonURL = try fixture.writeSafariExportJSON(
            records: [
                .init(url: "https://merge.example/a", timeUsec: sharedTimeUsec, title: "A", visitCount: 3),
                .init(url: "https://merge.example/a", timeUsec: sharedTimeUsec, title: "A again", visitCount: 5)
            ]
        )

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: jsonURL,
            modelContext: fixture.context,
            preferredFormat: .safari,
            dedupOptions: ImportDedupOptions(enableNearDuplicateTolerance: false, nearDuplicateToleranceSeconds: 0)
        )

        #expect(report.importedRecordCount == 1)
        #expect(report.skippedRecordCount == 1)
        #expect(try fixture.recordCount() == 1)
        #expect(try fixture.firstItem()?.visitCount == 8)
    }

    @Test("Duplicate cleaner merges visit counts into the kept record")
    func duplicateCleanerMergesVisitCounts() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        try fixture.insertItem(
            url: "https://mergeclean.example",
            title: "A",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "a",
            visitCount: 2
        )
        try fixture.insertItem(
            url: "https://mergeclean.example",
            title: "B",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_001),
            browser: "Safari",
            uniqueKey: "b",
            visitCount: 4
        )

        let cleaner = HistoryDuplicateCleaner()
        let report = try await cleaner.deduplicate(
            modelContainer: fixture.container,
            dedupOptions: ImportDedupOptions(enableNearDuplicateTolerance: true, nearDuplicateToleranceSeconds: 1)
        )

        #expect(report.removedCount == 1)
        #expect(try fixture.recordCount() == 1)
        #expect(try fixture.firstItem()?.visitCount == 6)
    }

    @Test("HistoryLib import accepts a valid empty archive")
    func historyLibImportAcceptsEmptyArchive() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let archiveRoot = try fixture.writeHistoryLibArchive(chunks: [])

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: archiveRoot,
            modelContext: fixture.context,
            preferredFormat: .historyLib
        )

        #expect(report.importedRecordCount == 0)
        #expect(try fixture.recordCount() == 0)
    }

    @Test("HistoryLib import rejects a chunk whose checksum does not match")
    func historyLibImportRejectsChecksumMismatch() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let archiveRoot = try fixture.writeHistoryLibArchive(
            chunks: [["{\"u\":\"https://a.example\",\"ts\":1710000000000000}"]],
            corruptShaForChunkID: 1
        )

        let importer = HistoryImporter()
        await #expect(throws: (any Error).self) {
            _ = try await importer.importFrom(
                url: archiveRoot,
                modelContext: fixture.context,
                preferredFormat: .historyLib
            )
        }
        #expect(try fixture.recordCount() == 0)
    }

    @Test("HistoryLib import rejects a record_count that does not match the chunks")
    func historyLibImportRejectsRecordCountMismatch() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let archiveRoot = try fixture.writeHistoryLibArchive(
            chunks: [["{\"u\":\"https://a.example\",\"ts\":1710000000000000}"]],
            manifestRecordCountOverride: 99
        )

        let importer = HistoryImporter()
        await #expect(throws: (any Error).self) {
            _ = try await importer.importFrom(
                url: archiveRoot,
                modelContext: fixture.context,
                preferredFormat: .historyLib
            )
        }
        #expect(try fixture.recordCount() == 0)
    }

    @Test("HistoryLib import rejects a malformed chunk record")
    func historyLibImportRejectsMalformedRecord() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        // Valid JSON but missing the required `u`/`ts` fields.
        let archiveRoot = try fixture.writeHistoryLibArchive(
            chunks: [["{\"t\":\"no url or ts\"}"]]
        )

        let importer = HistoryImporter()
        await #expect(throws: (any Error).self) {
            _ = try await importer.importFrom(
                url: archiveRoot,
                modelContext: fixture.context,
                preferredFormat: .historyLib
            )
        }
    }

    @Test("HistoryLib import rejects a chunk path that escapes the archive root")
    func historyLibImportRejectsPathTraversal() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let archiveRoot = try fixture.writeHistoryLibArchive(
            chunks: [["{\"u\":\"https://a.example\",\"ts\":1710000000000000}"]],
            chunkPathOverrideForID: [1: "../escaped.jsonl"]
        )

        let importer = HistoryImporter()
        await #expect(throws: (any Error).self) {
            _ = try await importer.importFrom(
                url: archiveRoot,
                modelContext: fixture.context,
                preferredFormat: .historyLib
            )
        }
        #expect(try fixture.recordCount() == 0)
    }

    @Test("ZIP extraction rejects entries that escape the destination directory")
    func zipExtractionRejectsPathTraversal() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let zipURL = try fixture.writeZipWithEntry(path: "../escaped.json", contents: Data("x".utf8))
        let destination = fixture.tempDirectoryURL.appendingPathComponent("extract-\(UUID().uuidString)", isDirectory: true)

        #expect(throws: (any Error).self) {
            try ImportZipArchive.extractZip(at: zipURL, to: destination)
        }
    }

    @Test("ZIP entry path normalization accepts legitimate paths and rejects escapes")
    func zipEntryPathNormalization() {
        // Legitimate relative paths are preserved (independent of any symlinked
        // temp directory, which is what broke import on iOS).
        #expect(ImportZipArchive.safeRelativePath("manifest.json") == "manifest.json")
        #expect(ImportZipArchive.safeRelativePath("chunks/00000001.jsonl") == "chunks/00000001.jsonl")
        #expect(ImportZipArchive.safeRelativePath("./manifest.json") == "manifest.json")
        #expect(ImportZipArchive.safeRelativePath("archive/./chunks/x.jsonl") == "archive/chunks/x.jsonl")
        #expect(ImportZipArchive.safeRelativePath("a/../b.json") == "b.json")
        #expect(ImportZipArchive.safeRelativePath("chunks\\00000001.jsonl") == "chunks/00000001.jsonl")
        #expect(ImportZipArchive.safeRelativePath("") == "")
        #expect(ImportZipArchive.safeRelativePath("./") == "")

        // Escapes and absolute paths are rejected.
        #expect(ImportZipArchive.safeRelativePath("../escaped.json") == nil)
        #expect(ImportZipArchive.safeRelativePath("a/../../escaped.json") == nil)
        #expect(ImportZipArchive.safeRelativePath("/etc/passwd") == nil)
    }
}

private struct TestFixture {
    struct SafariRecord {
        let url: String
        let timeUsec: Int64
        let title: String
        var visitCount: Int = 1
    }

    let container: ModelContainer
    let context: ModelContext
    let tempDirectoryURL: URL

    init() throws {
        let schema = Schema([Item.self, SummarySnapshot.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)

        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryLibTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    func recordCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Item>())
    }

    func firstItem() throws -> Item? {
        try context.fetch(FetchDescriptor<Item>()).first
    }

    func insertItem(
        url: String,
        title: String,
        visitedAt: Date,
        browser: String,
        uniqueKey: String,
        visitCount: Int = 1
    ) throws {
        let item = Item(
            uniqueKey: uniqueKey,
            url: url,
            title: title,
            visitedAt: visitedAt,
            visitCount: visitCount,
            sourceBrowser: browser,
            sourceFileName: "fixture.json",
            rawTimeUsec: Int64((visitedAt.timeIntervalSince1970 * 1_000_000).rounded()),
            importedAt: visitedAt
        )
        context.insert(item)
        try context.save()
    }

    func writeSafariExportJSON(records: [SafariRecord]) throws -> URL {
        let payload: [String: Any] = [
            "metadata": [
                "browser_name": "Safari",
                "browser_version": "17.0",
                "data_type": "history",
                "export_time_usec": Int64((Date().timeIntervalSince1970 * 1_000_000).rounded()),
                "schema_version": 1
            ],
            "history": records.map { record in
                [
                    "url": record.url,
                    "time_usec": record.timeUsec,
                    "visit_count": record.visitCount,
                    "title": record.title
                ]
            }
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let outputURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    /// Builds a HistoryLib archive directory (manifest + chunks + chunk index)
    /// on disk and returns its root. Overrides let tests inject corruption.
    func writeHistoryLibArchive(
        chunks: [[String]],
        corruptShaForChunkID: Int? = nil,
        manifestRecordCountOverride: Int? = nil,
        chunkPathOverrideForID: [Int: String] = [:]
    ) throws -> URL {
        let fm = FileManager.default
        let archiveRoot = tempDirectoryURL.appendingPathComponent("archive-\(UUID().uuidString)", isDirectory: true)
        let chunksDir = archiveRoot.appendingPathComponent("chunks", isDirectory: true)
        let indexesDir = archiveRoot.appendingPathComponent("indexes", isDirectory: true)
        try fm.createDirectory(at: chunksDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: indexesDir, withIntermediateDirectories: true)

        var indexEntries: [[String: Any]] = []
        var totalRecords = 0

        for (offset, lines) in chunks.enumerated() {
            let id = offset + 1
            let fileName = String(format: "%08d.jsonl", id)
            let physicalURL = chunksDir.appendingPathComponent(fileName)
            let body = lines.map { $0 + "\n" }.joined()
            let data = Data(body.utf8)
            try data.write(to: physicalURL, options: .atomic)

            let sha: String
            if corruptShaForChunkID == id {
                sha = String(repeating: "0", count: 64)
            } else {
                sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }

            let indexPath = chunkPathOverrideForID[id] ?? "chunks/\(fileName)"
            totalRecords += lines.count
            indexEntries.append([
                "id": id,
                "path": indexPath,
                "record_count": lines.count,
                "min_ts": 0,
                "max_ts": 0,
                "sha256": sha
            ])
        }

        let chunksIndexData = try JSONSerialization.data(withJSONObject: indexEntries, options: [])
        try chunksIndexData.write(to: indexesDir.appendingPathComponent("chunks.json"), options: .atomic)

        let manifest: [String: Any] = [
            "format": "historylib",
            "format_version": 1,
            "record_count": manifestRecordCountOverride ?? totalRecords,
            "chunk_count": chunks.count,
            "indexes": ["chunks": "indexes/chunks.json"]
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [])
        try manifestData.write(to: archiveRoot.appendingPathComponent("manifest.json"), options: .atomic)

        return archiveRoot
    }

    /// Creates a ZIP archive containing a single entry at the given (possibly
    /// unsafe) path. Used to exercise path-traversal rejection.
    func writeZipWithEntry(path: String, contents: Data) throws -> URL {
        let zipURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).zip")
        let archive = try Archive(url: zipURL, accessMode: .create, pathEncoding: nil)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(contents.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, contents.count)
            return contents.subdata(in: start..<end)
        }
        return zipURL
    }
}
