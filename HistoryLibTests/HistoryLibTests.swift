import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import History_Lib

@Suite("History Data Path Tests")
@MainActor
struct HistoryLibTests {
    @Test("Safari import applies strict dedup for exact duplicates")
    func safariImportStrictDedup() throws {
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
        let report = try importer.importFrom(
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
    func safariImportNearDuplicateDefaultEnabled() throws {
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
        _ = try importer.importFrom(url: firstURL, modelContext: fixture.context, preferredFormat: .safari)
        let secondReport = try importer.importFrom(url: secondURL, modelContext: fixture.context, preferredFormat: .safari)

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
        let report = try importer.importFrom(
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
        let report = try importer.importFrom(
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
        let report = try importer.importFrom(
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
}

private struct TestFixture {
    struct SafariRecord {
        let url: String
        let timeUsec: Int64
        let title: String
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

    func insertItem(
        url: String,
        title: String,
        visitedAt: Date,
        browser: String,
        uniqueKey: String
    ) throws {
        let item = Item(
            uniqueKey: uniqueKey,
            url: url,
            title: title,
            visitedAt: visitedAt,
            visitCount: 1,
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
                    "visit_count": 1,
                    "title": record.title
                ]
            }
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let outputURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }
}
