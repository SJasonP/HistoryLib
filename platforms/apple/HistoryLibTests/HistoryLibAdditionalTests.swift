import Foundation
import Testing
@testable import History_Lib

@MainActor
extension HistoryLibTests {
    @Test("HistoryLib import accepts a valid empty archive")
    func historyLibImportAcceptsEmptyArchive() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let archiveRoot = try fixture.writeHistoryLibArchive(chunks: [])

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: archiveRoot,
            modelContext: fixture.context
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
                modelContext: fixture.context
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
                modelContext: fixture.context
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
                modelContext: fixture.context
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
                modelContext: fixture.context
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

    @Test("Directory count cache snapshot round-trips through JSON")
    func directoryCountSnapshotRoundTrips() throws {
        let snapshot = DirectoryCountSnapshot(
            schemaVersion: DirectoryCountCache.schemaVersion,
            timeZoneIdentifier: "America/New_York",
            totalCount: 7,
            days: [
                DayCountEntry(day: 1_710_000_000, count: 3),
                DayCountEntry(day: 1_709_913_600, count: 4)
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DirectoryCountSnapshot.self, from: data)

        #expect(decoded.schemaVersion == DirectoryCountCache.schemaVersion)
        #expect(decoded.timeZoneIdentifier == "America/New_York")
        #expect(decoded.totalCount == 7)
        #expect(decoded.days.count == 2)
        #expect(decoded.days.reduce(0) { $0 + $1.count } == decoded.totalCount)

        let byDay = Dictionary(uniqueKeysWithValues: decoded.days.map { ($0.day, $0.count) })
        #expect(byDay[1_710_000_000] == 3)
        #expect(byDay[1_709_913_600] == 4)
    }

    @Test("Collapsing a large hierarchy prunes only its descendant expansion state")
    func hierarchyCollapsePrunesDescendants() {
        let january = Date(timeIntervalSince1970: 1_735_689_600)
        let february = Date(timeIntervalSince1970: 1_738_368_000)
        let unrelatedMonth = Date(timeIntervalSince1970: 1_767_225_600)
        let januaryDay = january
        let februaryDay = february
        let unrelatedDay = unrelatedMonth
        let yearGroup = HistoryYearGroup(
            year: 2025,
            title: "2025",
            monthGroups: [
                HistoryMonthGroup(
                    monthStart: january,
                    title: "January 2025",
                    dayGroups: [HistoryDayGroup(dayStart: januaryDay, title: "January 1")]
                ),
                HistoryMonthGroup(
                    monthStart: february,
                    title: "February 2025",
                    dayGroups: [HistoryDayGroup(dayStart: februaryDay, title: "February 1")]
                )
            ]
        )

        var years: Set<Int> = [2025, 2026]
        var months: Set<Date> = [january, february, unrelatedMonth]
        var days: Set<Date> = [januaryDay, februaryDay, unrelatedDay]
        let releasedDays = HistoryHierarchyExpansion.collapse(
            yearGroup,
            years: &years,
            months: &months,
            days: &days
        )

        #expect(years == [2026])
        #expect(months == [unrelatedMonth])
        #expect(days == [unrelatedDay])
        #expect(Set(releasedDays) == [januaryDay, februaryDay])
    }

    @Test("Clear Cache storage usage separates clearable cache from non-clearable data")
    func clearCacheStorageUsageSeparatesCategories() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let root = fixture.tempDirectoryURL.appendingPathComponent("storage-usage", isDirectory: true)
        let dataContainer = root.appendingPathComponent("data-container", isDirectory: true)
        let libraryDirectory = dataContainer.appendingPathComponent("Library", isDirectory: true)
        let cachesDirectory = libraryDirectory.appendingPathComponent("Caches", isDirectory: true)
        let faviconDirectory = cachesDirectory.appendingPathComponent("favicons", isDirectory: true)
        let temporaryDirectory = dataContainer.appendingPathComponent("tmp", isDirectory: true)
        let applicationSupport = libraryDirectory.appendingPathComponent("Application Support", isDirectory: true)
        let cloudKitDirectory = libraryDirectory.appendingPathComponent("cloudkit", isDirectory: true)
        let cloudKitAssets = applicationSupport.appendingPathComponent("default_ckAssets", isDirectory: true)
        let importTemporaryDirectory = temporaryDirectory.appendingPathComponent("Import", isDirectory: true)
        for directory in [faviconDirectory, importTemporaryDirectory, applicationSupport, cloudKitDirectory, cloudKitAssets] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let favicon = faviconDirectory.appendingPathComponent("example.bin")
        let directoryCountCache = applicationSupport.appendingPathComponent("directory-count-cache.json")
        let temporaryFile = importTemporaryDirectory.appendingPathComponent("stale-import.bin")
        let store = applicationSupport.appendingPathComponent("default.store")
        let wal = applicationSupport.appendingPathComponent("default.store-wal")
        let shm = applicationSupport.appendingPathComponent("default.store-shm")
        let cloudAsset = cloudKitAssets.appendingPathComponent("asset.bin")
        let cloudMetadata = cloudKitDirectory.appendingPathComponent("metadata.bin")
        let unrelated = applicationSupport.appendingPathComponent("unrelated.bin")
        let files = [favicon, directoryCountCache, temporaryFile, store, wal, shm, cloudAsset, cloudMetadata, unrelated]
        for (index, file) in files.enumerated() {
            try Data(repeating: UInt8(index), count: 1_024 + index).write(to: file)
        }

        let usage = ClearCacheStorageUsageCalculator.measure(
            cachesDirectory: cachesDirectory,
            temporaryDirectory: temporaryDirectory,
            directoryCountCacheURL: directoryCountCache,
            dataContainerDirectory: dataContainer,
            databaseURLs: [store]
        )
        let allocatedSize: (URL) -> Int64 = { url in
            let keys: Set<URLResourceKey> = [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]
            let values = try? url.resourceValues(forKeys: keys)
            return Int64(
                values?.totalFileAllocatedSize
                    ?? values?.fileAllocatedSize
                    ?? values?.fileSize
                    ?? 0
            )
        }

        #expect(
            usage.clearableCacheBytes
                == allocatedSize(favicon) + allocatedSize(temporaryFile) + allocatedSize(directoryCountCache)
        )
        #expect(
            usage.nonClearableDataBytes
                == [cloudAsset, cloudMetadata, unrelated]
                    .reduce(0) { $0 + allocatedSize($1) }
        )
        #expect(usage.databaseBytes == allocatedSize(store) + allocatedSize(wal) + allocatedSize(shm))

        ClearCacheStorageUsageCalculator.clearDirectoryContents(at: cachesDirectory)
        ClearCacheStorageUsageCalculator.clearDirectoryContents(at: temporaryDirectory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cachesDirectory.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path).isEmpty)
    }

    // MARK: - Chrome (Google Takeout)

    @Test("Chrome Takeout export is auto-detected and mapped onto history records")
    func chromeTakeoutImportMapsRecords() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        // 2024-04-02T20:58:31.057699Z, as Takeout writes it: Unix-epoch microseconds.
        let timeUsec: Int64 = 1_712_091_511_057_699
        let jsonURL = try fixture.writeChromeTakeoutJSON(
            records: [
                TestFixture.chromeRecord(url: "https://example.com/a", timeUsec: timeUsec, title: "A")
            ]
        )

        let report = try await HistoryImporter().importFrom(url: jsonURL, modelContext: fixture.context)

        #expect(report.format == .chrome)
        #expect(report.importedRecordCount == 1)
        #expect(try fixture.recordCount() == 1)

        let item = try #require(try fixture.firstItem())
        #expect(item.url == "https://example.com/a")
        #expect(item.title == "A")
        #expect(item.sourceBrowser == "Chrome")
        // Takeout carries no visit_count; each entry is exactly one visit.
        #expect(item.visitCount == 1)
        // rawTimeUsec must stay Unix-epoch microseconds: the .hlz exporter emits it verbatim.
        #expect(item.rawTimeUsec == timeUsec)
        #expect(abs(item.visitedAt.timeIntervalSince1970 - Double(timeUsec) / 1_000_000) < 0.001)
        // Fields with no Takeout equivalent stay empty.
        #expect(item.sourceURL == nil)
        #expect(item.destinationURL == nil)
        #expect(item.latestVisitWasHTTPGet == nil)
    }

    @Test("Chrome Takeout time_usec is accepted as a JSON string")
    func chromeTakeoutAcceptsStringTimeUsec() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let timeUsec: Int64 = 1_712_091_511_057_699
        let jsonURL = try fixture.writeChromeTakeoutJSON(
            records: [
                TestFixture.chromeRecord(url: "https://example.com/a", timeUsec: String(timeUsec), title: "A")
            ]
        )

        let report = try await HistoryImporter().importFrom(url: jsonURL, modelContext: fixture.context)

        #expect(report.importedRecordCount == 1)
        let item = try #require(try fixture.firstItem())
        #expect(item.rawTimeUsec == timeUsec)
    }

    @Test("Chrome Takeout records missing a url or time_usec are skipped")
    func chromeTakeoutSkipsIncompleteRecords() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let timeUsec: Int64 = 1_712_091_511_057_699
        let jsonURL = try fixture.writeChromeTakeoutJSON(
            records: [
                TestFixture.chromeRecord(url: "https://example.com/a", timeUsec: timeUsec, title: "A"),
                ["title": "no url", "time_usec": timeUsec],
                ["title": "no time", "url": "https://example.com/b"],
                TestFixture.chromeRecord(url: "   ", timeUsec: timeUsec, title: "blank url")
            ]
        )

        let report = try await HistoryImporter().importFrom(url: jsonURL, modelContext: fixture.context)

        #expect(report.importedRecordCount == 1)
        #expect(report.skippedRecordCount == 3)
        #expect(try fixture.recordCount() == 1)
    }

    @Test("Chrome Takeout zip is auto-detected and imported")
    func chromeTakeoutZipImports() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let timeUsec: Int64 = 1_712_091_511_057_699
        let jsonURL = try fixture.writeChromeTakeoutJSON(
            records: [
                TestFixture.chromeRecord(url: "https://example.com/a", timeUsec: timeUsec, title: "A"),
                TestFixture.chromeRecord(url: "https://example.com/b", timeUsec: timeUsec + 5_000_000, title: "B")
            ],
            directoryName: "Chrome"
        )
        let zipURL = try fixture.zipDirectory(jsonURL.deletingLastPathComponent())

        let report = try await HistoryImporter().importFrom(url: zipURL, modelContext: fixture.context)

        #expect(report.format == .chrome)
        #expect(report.importedRecordCount == 2)
        #expect(try fixture.recordCount() == 2)
    }

    @Test("A Takeout folder imports only its history file, ignoring sibling JSON")
    func chromeTakeoutFolderIgnoresUnrelatedJSON() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let timeUsec: Int64 = 1_712_091_511_057_699
        let historyURL = try fixture.writeChromeTakeoutJSON(
            records: [
                TestFixture.chromeRecord(url: "https://example.com/a", timeUsec: timeUsec, title: "A")
            ],
            directoryName: "Chrome"
        )
        let takeoutDirectory = historyURL.deletingLastPathComponent()

        // Real Takeout folders sit next to unrelated exports.
        let autofill = try JSONSerialization.data(withJSONObject: ["Autofill": []], options: [])
        try autofill.write(to: takeoutDirectory.appendingPathComponent("Autofill.json"), options: .atomic)

        let report = try await HistoryImporter().importFrom(url: takeoutDirectory, modelContext: fixture.context)

        #expect(report.format == .chrome)
        #expect(report.importedRecordCount == 1)
        // Both JSON files are scanned, but only the history file is a valid source
        // and the unrelated sibling is not reported as a failure.
        #expect(report.scannedFileCount == 2)
        #expect(report.validFileCount == 1)
        #expect(report.failures.isEmpty)
    }

    @Test("Chrome detection does not misfire on a Safari export named History.json")
    func safariExportIsNotDetectedAsChrome() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let jsonURL = try fixture.writeSafariExportJSON(
            records: [.init(url: "https://example.com/a", timeUsec: 1_710_000_000_000_000, title: "A")]
        )

        let report = try await HistoryImporter().importFrom(url: jsonURL, modelContext: fixture.context)

        #expect(report.format == .safari)
        let item = try #require(try fixture.firstItem())
        #expect(item.sourceBrowser == "Safari")
    }

    @Test("A record titled \"Browser History\" is not mistaken for a Chrome export")
    func safariRecordTitledBrowserHistoryIsNotChrome() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        // The literal "Browser History" appears in the file, but as a value rather
        // than a key, so the key-with-colon sniff must reject it.
        let jsonURL = try fixture.writeChromeTakeoutJSON(
            records: [],
            fileName: "Decoy.json"
        )
        let decoy = try JSONSerialization.data(
            withJSONObject: ["history": [["title": "Browser History", "url": "https://example.com"]]],
            options: []
        )
        try decoy.write(to: jsonURL, options: .atomic)

        #expect(ChromeHistoryImporter().looksLikeChromeHistorySource(jsonURL) == false)
    }

    @Test("Chrome records survive an .hlz round-trip with browser and timestamp intact")
    func chromeRecordsSurviveHistoryLibRoundTrip() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let timeUsec: Int64 = 1_712_091_511_057_699
        let jsonURL = try fixture.writeChromeTakeoutJSON(
            records: [
                TestFixture.chromeRecord(url: "https://example.com/a", timeUsec: timeUsec, title: "A")
            ]
        )
        _ = try await HistoryImporter().importFrom(url: jsonURL, modelContext: fixture.context)

        let exporter = HistoryExporter()
        let prepared = try await exporter.prepareExportFile(
            modelContext: fixture.context,
            format: .historyLib,
            split: .single
        )
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectoryURL) }

        // Re-import into a clean store and confirm nothing drifted.
        let reimportFixture = try TestFixture()
        defer { reimportFixture.cleanup() }
        let report = try await HistoryImporter().importFrom(
            url: prepared.fileURL,
            modelContext: reimportFixture.context
        )

        #expect(report.importedRecordCount == 1)
        let item = try #require(try reimportFixture.firstItem())
        #expect(item.sourceBrowser == "Chrome")
        #expect(item.url == "https://example.com/a")
        // The guard against a wrong epoch: a 1601-based value would land in 1601.
        #expect(item.rawTimeUsec == timeUsec)
        #expect(abs(item.visitedAt.timeIntervalSince1970 - Double(timeUsec) / 1_000_000) < 0.001)
    }

    @Test("Google Takeout export writes the Browser History JSON shape")
    func googleTakeoutExportWritesCanonicalJSON() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let visitedAt = Date(timeIntervalSince1970: 1_712_091_511.057699)
        try fixture.insertItem(
            url: "https://example.com/\"quoted\"",
            title: "A title with \"quotes\"",
            visitedAt: visitedAt,
            browser: "Chrome",
            uniqueKey: "takeout-key"
        )

        let prepared = try await HistoryExporter().prepareExportFile(
            modelContext: fixture.context,
            format: .googleTakeout,
            split: .single,
            password: "ignored"
        )
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectoryURL) }

        #expect(prepared.fileURL.pathExtension == "json")
        let data = try Data(contentsOf: prepared.fileURL)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try #require(object["Browser History"] as? [[String: Any]])
        let record = try #require(records.first)
        #expect(record["url"] as? String == "https://example.com/\"quoted\"")
        #expect(record["title"] as? String == "A title with \"quotes\"")
        #expect(record["time_usec"] as? Int64 == 1_712_091_511_057_699)
    }

    @Test("Large Chrome Takeout files stream through multiple database batches")
    func chromeTakeoutStreamsLargeRecordSet() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let baseTime: Int64 = 1_712_091_511_057_699
        let records = (0..<2_500).map { index in
            TestFixture.chromeRecord(
                url: "https://example.com/\(index)",
                timeUsec: baseTime + Int64(index) * 2_000_000,
                title: "Record {\(index)} with an escaped quote: \""
            )
        }
        let jsonURL = try fixture.writeChromeTakeoutJSON(records: records)

        let report = try await HistoryImporter().importFrom(url: jsonURL, modelContext: fixture.context)

        #expect(report.importedRecordCount == records.count)
        #expect(report.skippedRecordCount == 0)
        #expect(try fixture.recordCount() == records.count)
    }

    @Test("A truncated Chrome Takeout file is reported as damaged")
    func chromeTakeoutRejectsTruncatedJSON() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let jsonURL = fixture.tempDirectoryURL.appendingPathComponent("History.json")
        try Data(#"{"Browser History":[{"url":"https://example.com","time_usec":1712091511057699}"#.utf8)
            .write(to: jsonURL)

        await #expect(throws: ChromeTakeoutStreamError.self) {
            _ = try await ChromeTakeoutStreamParser().parse(url: jsonURL) { _ in }
        }
    }
}
