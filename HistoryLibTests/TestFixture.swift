import CryptoKit
import Foundation
import SwiftData
import ZIPFoundation
@testable import History_Lib

struct TestFixture {
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

    /// Writes a Google Takeout Chrome history export. Records are emitted with
    /// whatever keys the caller supplies, so tests can omit fields or pass
    /// `time_usec` as a string. `directoryName` places the file under a named
    /// folder to exercise browser-name inference.
    func writeChromeTakeoutJSON(
        records: [[String: Any]],
        fileName: String = "History.json",
        directoryName: String? = nil
    ) throws -> URL {
        let payload: [String: Any] = ["Browser History": records]

        var outputDirectory = tempDirectoryURL
        if let directoryName {
            outputDirectory = tempDirectoryURL
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(directoryName, isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let outputURL = outputDirectory.appendingPathComponent(fileName)
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    /// Convenience for the common "one plain visit" Takeout record.
    static func chromeRecord(url: String, timeUsec: Any, title: String) -> [String: Any] {
        [
            "favicon_url": "https://example.com/favicon.ico",
            "page_transition": "LINK",
            "title": title,
            "url": url,
            "client_id": "abc123==",
            "time_usec": timeUsec
        ]
    }

    /// Zips an existing directory so ZIP-path tests can reuse the JSON writers.
    func zipDirectory(_ directoryURL: URL) throws -> URL {
        let zipURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).zip")
        try FileManager.default.zipItem(at: directoryURL, to: zipURL, shouldKeepParent: true)
        return zipURL
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

