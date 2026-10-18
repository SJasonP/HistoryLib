import AppIntents
import Testing
@testable import History_Lib

@MainActor
@Suite("History Search Intents")
struct HistorySearchIntentTests {
    @Test("App Intents route requests without reading or returning history")
    func intents() async throws {
        let router = HistorySearchRequests.shared
        defer { _ = router.consume(isBusy: false) }
        var search = SearchHistoryIntent()
        search.query = "Swift"
        _ = try await search.perform()
        #expect(router.consume(isBusy: false)?.query == "Swift")
        var natural = PrepareNaturalHistorySearchIntent()
        natural.query = "last month on GitHub"
        _ = try await natural.perform()
        #expect(router.consume(isBusy: false)?.mode == .naturalLanguage)
        if #available(iOS 27.0, macOS 27.0, *) {
            var siri = SearchHistoryWithSiriIntent()
            siri.criteria = StringSearchCriteria(term: "documentation")
            _ = try await siri.perform()
            #expect(router.consume(isBusy: false)?.query == "documentation")
        }
    }
}
