import Foundation
import Testing
@testable import History_Lib

@MainActor
@Suite("Release Readiness")
struct ReleaseReadinessTests {
    @Test("Memory recovery never accepts history mutations, regardless of sync settings")
    func recoveryIsReadOnly() {
        for sync in [true, false] {
            for launchSync in [true, false] {
                #expect(!HistoryStoragePolicy.canMutate(backend: "memoryFallback", syncEnabled: sync, launchSyncEnabled: launchSync))
            }
        }
        #expect(HistoryStoragePolicy.canMutate(backend: "localUserDisabledICloud", syncEnabled: false, launchSyncEnabled: false))
        #expect(HistoryStoragePolicy.canMutate(backend: "cloudKit", syncEnabled: true, launchSyncEnabled: true))
        #expect(!HistoryStoragePolicy.canMutate(backend: "localFallback", syncEnabled: true, launchSyncEnabled: true))
        #expect(!HistoryStoragePolicy.canMutate(backend: "cloudKit", syncEnabled: false, launchSyncEnabled: true))
        #expect(!HistoryStoragePolicy.canMutate(backend: "localUserDisabledICloud", syncEnabled: true, launchSyncEnabled: false))
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
