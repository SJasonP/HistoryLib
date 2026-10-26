import Foundation
import SwiftData
import Testing
@testable import History_Lib

@MainActor
@Suite("Release Readiness")
struct ReleaseReadinessTests {
    @Test("Only an opened primary store accepts history mutations")
    func recoveryIsReadOnly() {
        #expect(!HistoryStoragePolicy.canMutate(backend: "memoryFallback"))
        #expect(HistoryStoragePolicy.canMutate(backend: "primary"))
        #expect(!HistoryStoragePolicy.canMutate(backend: "localFallback"))
        #expect(!HistoryStoragePolicy.canMutate(backend: "unknown"))
    }

    @Test("A sync failure does not prevent local insertion or deletion")
    func syncFailureLeavesPrimaryWritable() throws {
        let activity = HistorySyncActivity()
        activity.bind(storeIdentifiers: ["fictional-store"])
        activity.receive(identifier: UUID(), store: "fictional-store", phase: .upload,
                         endDate: Date(), succeeded: false, hasError: true)
        #expect(activity.hasObservedFailure)
        let container = try ModelContainer(for: Item.self, configurations:
            ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        try #require(HistoryStoragePolicy.canMutate(backend: "primary"))
        let item = Item(uniqueKey: "sync-error-fixture", url: "https://example.test/",
                        title: "Fictional record", visitedAt: Date(), visitCount: 1,
                        sourceBrowser: "Safari", sourceFileName: "fixture", rawTimeUsec: 0)
        context.insert(item)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 1)
        try #require(HistoryStoragePolicy.canMutate(backend: "primary"))
        context.delete(item)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(activity.hasObservedFailure)
    }

    @Test("Favicon lookup drops recorded path, query, fragment, and credentials")
    func faviconOriginOnly() throws {
        let recorded = try #require(URL(string: "https://user:secret@example.com:8443/private/action?token=secret#account"))
        let origin = try #require(FaviconRequestPolicy.origin(for: recorded))
        #expect(origin.absoluteString == "https://example.com:8443/")
        let requests = FaviconRequestPolicy.fallbackURLs(for: recorded)
        #expect(requests.count == 3)
        for request in requests {
            #expect(request.host == "example.com")
            #expect(request.port == 8443)
            #expect(request.query == nil && request.fragment == nil && request.user == nil && request.password == nil)
            #expect(!request.absoluteString.contains("secret"))
        }
        #expect(FaviconRequestPolicy.origin(for: URL(string: "file:///private/history")!) == nil)
    }

    @Test("Discovered icons cannot change origin or downgrade HTTPS")
    func faviconOriginBoundary() {
        let origin = URL(string: "https://example.com/")!
        #expect(FaviconRequestPolicy.permitsIcon(URL(string: "https://example.com/icon.png")!, from: origin))
        #expect(FaviconRequestPolicy.permitsIcon(URL(string: "https://example.com:443/icon.png")!, from: origin))
        for candidate in ["http://example.com/icon.png", "https://other.test/icon.png", "https://example.com:8443/icon.png", "https://user:secret@example.com/icon.png"] {
            #expect(!FaviconRequestPolicy.permitsIcon(URL(string: candidate)!, from: origin))
        }
        #expect(FaviconRequestPolicy.fallbackURLs(for: origin).allSatisfy { $0.scheme == "https" })
    }
}
