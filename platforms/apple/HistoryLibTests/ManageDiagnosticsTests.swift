import Foundation
import SQLite3
import SwiftData
import Testing
@testable import History_Lib

@MainActor
@Suite("Manage diagnostics and journal reclamation")
struct ManageDiagnosticsTests {
    @Test("Journal maintenance never creates a missing store or modifies non-database files")
    func refusesNonDatabaseFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing.store")
        #expect(DatabaseJournalMaintenance.checkpoint(at: missing) == .completed)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        let other = root.appendingPathComponent("fixture.txt")
        let original = Data("Fictional non-database file".utf8)
        try original.write(to: other)
        #expect(DatabaseJournalMaintenance.checkpoint(at: other) == .unavailable)
        #expect(try Data(contentsOf: other) == original)
    }

    @Test("Cancellation discards an unfinished Manage measurement and stops refresh work")
    func monitoringCancellation() async {
        let diagnostics = ManageDiagnostics()
        var counts = 0
        let task = Task { @MainActor in
            await diagnostics.monitorLocal(count: { counts += 1; return 42 }, measure: {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(1)) } catch { break }
                }
                return ClearCacheStorageUsage(clearableCacheBytes: 1, nonClearableDataBytes: 2)
            })
        }
        while counts == 0 { await Task.yield() }
        task.cancel()
        await task.value
        #expect(counts == 1)
        #expect(diagnostics.storageUsage == nil)
    }

    @Test("WAL reclamation respects active readers and preserves all committed records")
    func checkpointPreservesRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fictional.sqlite")
        var writer: OpaquePointer?
        #expect(sqlite3_open(file.path, &writer) == SQLITE_OK)
        let db = try #require(writer)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE records(id INTEGER PRIMARY KEY, value TEXT); INSERT INTO records VALUES(1,'fictional');", nil, nil, nil) == SQLITE_OK)
        var reader: OpaquePointer?
        #expect(sqlite3_open(file.path, &reader) == SQLITE_OK)
        let reading = try #require(reader)
        #expect(sqlite3_exec(reading, "BEGIN; SELECT * FROM records;", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "INSERT INTO records VALUES(2,'second fictional record');", nil, nil, nil) == SQLITE_OK)
        #expect(DatabaseJournalMaintenance.checkpoint(at: file) == .busy)
        #expect(sqlite3_exec(reading, "COMMIT;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(reading)
        #expect(DatabaseJournalMaintenance.checkpoint(at: file) == .completed)
        let wal = URL(fileURLWithPath: file.path + "-wal")
        #expect((try wal.resourceValues(forKeys: [.fileSizeKey])).fileSize == 0)
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM records", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == 2)
    }

    @Test("Unknown temporary files and SQLite scratch files are never disposable")
    func temporaryBoundaries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let imports = root.appendingPathComponent("Import")
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disposable = imports.appendingPathComponent("fictional.json")
        let scratch = root.appendingPathComponent("etilqs_sort")
        let journal = root.appendingPathComponent("default.store-wal")
        let payload = Data("fictional bytes".utf8)
        for file in [disposable, scratch, journal] { try payload.write(to: file) }
        ClearCacheStorageUsageCalculator.clearDisposableTemporaryDirectories(in: root)
        #expect(!FileManager.default.fileExists(atPath: disposable.path))
        #expect(try Data(contentsOf: scratch) == payload)
        #expect(try Data(contentsOf: journal) == payload)
    }

    @Test("Repeated disk-backed searches stay read-only and journal reclamation preserves SwiftData")
    func diskSearchAndCheckpoint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fictional.store")
        let config = ModelConfiguration(schema: Schema([Item.self]), url: file, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Item.self, configurations: config)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        for i in 0..<1_200 {
            context.insert(Item(uniqueKey: "disk-\(i)", url: "https://example.test/\(i)", title: "Fictional record", visitedAt: Date(timeIntervalSince1970: Double(i)), visitCount: 1, sourceBrowser: "Safari", sourceFileName: "fixture", rawTimeUsec: Int64(i)))
        }
        try context.save()
        for _ in 0..<3 {
            let reading = ModelContext(container)
            let page = try await HistorySearchEngine.page(in: reading, filter: HistorySearchFilter(keywords: ["absent"]), offset: 0, scanLimit: 100)
            #expect(page.records.isEmpty)
            #expect(!reading.hasChanges)
        }
        _ = await DatabaseJournalMaintenance.reclaim(databaseURLs: [file])
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 1_200)
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<Item>()) == 1_200)
        context.insert(Item(uniqueKey: "after-clear", url: "https://example.test/new", title: "After clear", visitedAt: Date(), visitCount: 1, sourceBrowser: "Safari", sourceFileName: "fixture", rawTimeUsec: 0))
        try context.save()
        #expect(try fresh.fetchCount(FetchDescriptor<Item>()) == 1_201)
    }
}
