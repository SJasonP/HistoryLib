import Foundation
import SwiftData
import Testing
@testable import History_Lib

@Suite("Timestamp storage migration")
@MainActor
struct TimestampMigrationTests {
    @Test("The pre-fix disk schema retains records when the optional integer timestamp is added")
    func migratesExistingStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("historylib-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appendingPathComponent("history.store")
        try autoreleasepool {
            let schema = Schema(PreTimestampSchema.models)
            let configuration = ModelConfiguration(schema: schema, url: store, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(PreTimestampSchema.Item())
            try context.save()
        }
        let schema = Schema([Item.self, SummarySnapshot.self])
        let configuration = ModelConfiguration(schema: schema, url: store, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.url == "https://migration.example/fictional")
        #expect(item.visitCount == 8)
        #expect(item.rawImportedAtUsec == nil)
        let record = try HLRecord(from: item, tsUsec: recordTimeUsec(from: item))
        #expect(record.ia == 1_710_000_000_000_000)
    }
}

/// The production Item shape before rawImportedAtUsec was introduced. The
/// nested entity keeps the same persistent entity name, without the new field.
private enum PreTimestampSchema {
    static var models: [any PersistentModel.Type] { [Item.self, SummarySnapshot.self] }

    @Model
    final class Item {
        #Index<Item>([\.visitedAt], [\.uniqueKey])
        var uniqueKey: String = "migration-fictional"
        var url: String = "https://migration.example/fictional"
        var title: String = "Fictional migration record"
        @Attribute(originalName: "timestamp") var visitedAt: Date = Date(timeIntervalSince1970: 1_710_000_000)
        var visitCount: Int = 8
        var sourceBrowser: String = "Safari"
        var sourceFileName: String = "synthetic-migration.json"
        var rawTimeUsec: Int64 = 1_710_000_000_000_000
        var sourceURL: String?
        var sourceTimeUsec: Int64?
        var destinationURL: String?
        var destinationTimeUsec: Int64?
        var latestVisitWasHTTPGet: Bool?
        var importedAt: Date = Date(timeIntervalSince1970: 1_710_000_000)
        init() {}
    }
}
