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

@MainActor
struct BuildCompatibilityTests {
    @Test func buildGateTreatsMissingBuildAsZeroAndHonorsCloudVersion() throws {
        let firstName = "HistoryLib.Tests.First.\(UUID())"
        let secondName = "HistoryLib.Tests.Second.\(UUID())"
        let first = try #require(UserDefaults(suiteName: firstName))
        let second = try #require(UserDefaults(suiteName: secondName))
        defer {
            first.removePersistentDomain(forName: firstName)
            second.removePersistentDomain(forName: secondName)
        }
        #expect(first.integer(forKey: AppVersionGate.storedBuildKey) == 0)
        guard case .normal = AppVersionGate.evaluate(defaults: first, currentBuild: 9) else {
            Issue.record("First install must be allowed")
            return
        }
        guard case .normal = AppVersionGate.evaluate(defaults: second, currentBuild: 8) else {
            Issue.record("Another device's older build must be allowed")
            return
        }
        guard case .requiresRecovery(currentBuild: 8, storedBuild: 9) = AppVersionGate.evaluate(defaults: first, currentBuild: 8) else {
            Issue.record("A downgrade on the same device must be blocked")
            return
        }
        #expect(first.integer(forKey: AppVersionGate.storedBuildKey) == 9)
        guard case .requiresRecovery(currentBuild: 8, storedBuild: 9) = AppVersionGate.evaluate(defaults: second, currentBuild: 8, cloudBuild: 9) else {
            Issue.record("A known newer cloud build must block the older client")
            return
        }
        second.set(true, forKey: AppVersionGate.localOnlyKey)
        guard case .normal = AppVersionGate.evaluate(defaults: second, currentBuild: 8, cloudBuild: 9) else {
            Issue.record("An isolated local-only library must work without using the newer cloud store")
            return
        }
        #expect(HistoryStoragePolicy.canMutate(backend: "localOnly"))
    }

    @Test func cloudBuildMarkersDoNotLetOlderClientsOverwriteNewerBuilds() {
        let prefix = CloudBuildVersion.prefix
        let values: [String: Any] = [prefix + "9": "1.4", prefix + "10": "1.4", prefix + "invalid": "ignored", "unrelated": 999]
        #expect(CloudBuildVersion.builds(in: values).max() == 10)
        #expect(Set(CloudBuildVersion.builds(in: values)) == Set([9, 10]))
    }

    @Test func localResetRemovesOnlyTheSpecifiedStoreAndSidecars() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("fixture.store")
        let names = ["fixture.store", "fixture.store-wal", "fixture.store-shm", "_fixture.store_SUPPORT"]
        for name in names {
            try Data("synthetic fixture".utf8).write(to: root.appendingPathComponent(name))
        }
        let other = root.appendingPathComponent("other.store")
        try Data("another device fixture".utf8).write(to: other)
        try LocalStoreReset.removeStore(at: store)
        for name in names {
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path))
        }
        #expect(FileManager.default.fileExists(atPath: other.path))
        try LocalStoreReset.removeStore(at: store)
    }
}
