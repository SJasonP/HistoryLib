import AppIntents
import Foundation
import SwiftData
import Testing
@testable import History_Lib

@MainActor
@Suite("History Search")
struct HistorySearchTests {
    @Test("Host matching rejects lookalikes and URL path matches")
    func domainBoundary() throws {
        let filter = try HistorySearchFilter(domain: "GitHub.com").validated()
        #expect(filter.matches(url: "https://docs.github.com/swift", title: "", browser: "Chrome", visitedAt: Date()))
        for url in ["https://notgithub.com/", "https://github.com.evil.test/", "https://example.com/github.com", "https://github.com@example.com/"] {
            #expect(!filter.matches(url: url, title: "", browser: "Chrome", visitedAt: Date()))
        }
        for domain in ["https://github.com", "github.com/path", "user@github.com", "github..com"] {
            #expect(throws: HistorySearchError.self) { try HistorySearchFilter(domain: domain).validated() }
        }
    }

    @Test("All terms, browser and half-open dates are combined")
    func combinedCriteria() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let filter = try HistorySearchFilter(
            keywords: ["SWIFT", "guide"], domain: "example.com", browser: "safari",
            startDate: start, endDate: end
        ).validated()
        #expect(filter.matches(url: "https://example.com/guide", title: "Swift", browser: "Safari", visitedAt: start))
        #expect(!filter.matches(url: "https://example.com/guide", title: "Swift", browser: "Safari", visitedAt: end))
        #expect(!filter.matches(url: "https://example.com/guide", title: "Swift", browser: "Chrome", visitedAt: start))
        #expect(!filter.matches(url: "https://example.com/", title: "Swift", browser: "Safari", visitedAt: start))
        #expect(throws: HistorySearchError.self) {
            try HistorySearchFilter(startDate: end, endDate: start).validated()
        }
    }

    @Test("Calendar dates use local day boundaries through DST")
    func localDates() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(try HistorySearchFilter.calendarDate("2026-03-08", timeZone: zone))
        let end = try #require(try HistorySearchFilter.calendarDate("2026-03-09", timeZone: zone))
        #expect(end.timeIntervalSince(start) == 23 * 3_600)
        for date in ["2026-02-30", "2026-3-8", "2026-03-08T00:00:00Z", "ignore instructions"] {
            #expect(throws: HistorySearchError.self) { try HistorySearchFilter.calendarDate(date, timeZone: zone) }
        }
    }

    @Test("Unusable generated filters never become executable searches")
    func rejectsModelOutput() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        for output in [
            GeneratedHistorySearch(supported: false, keywords: ["x"], domain: nil, browser: nil, startDay: nil, endDayExclusive: nil),
            GeneratedHistorySearch(supported: true, keywords: [], domain: nil, browser: nil, startDay: nil, endDayExclusive: nil),
            GeneratedHistorySearch(supported: true, keywords: [], domain: nil, browser: "Other", startDay: nil, endDayExclusive: nil),
            GeneratedHistorySearch(supported: true, keywords: [], domain: nil, browser: nil, startDay: "2026-10-18", endDayExclusive: "2026-10-01")
        ] {
            #expect(throws: HistorySearchError.self) { try NaturalLanguageHistorySearch.validate(output, timeZone: zone) }
        }
    }

    @Test("Paged structured searches do not skip chunk-boundary matches")
    func paging() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        for i in 0..<13 {
            try fixture.insertItem(
                url: "https://example.com/\(i)", title: i.isMultiple(of: 2) ? "Swift guide" : "Other",
                visitedAt: Date(timeIntervalSince1970: Double(i)), browser: "Safari", uniqueKey: "search-\(i)"
            )
        }
        let countBefore = try fixture.recordCount()
        let filter = HistorySearchFilter(keywords: ["Swift"], domain: "example.com", startDate: Date(timeIntervalSince1970: 2), endDate: Date(timeIntervalSince1970: 11))
        var cursor = 0
        var keys: [String] = []
        var more = true
        while more {
            let page = try await HistorySearchEngine.page(in: fixture.context, filter: filter, offset: cursor, scanLimit: 3, targetMatches: 1)
            cursor = page.nextOffset
            more = page.hasMore
            keys.append(contentsOf: page.records.map(\.uniqueKey))
        }
        #expect(keys == ["search-10", "search-8", "search-6", "search-4", "search-2"])
        #expect(Set(keys).count == keys.count)
        #expect(try fixture.recordCount() == countBefore)
    }

    @Test("Cancellation aborts search without modifying the store")
    func cancellation() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await HistorySearchEngine.page(in: fixture.context, filter: HistorySearchFilter(), offset: 0)
        }
        do { _ = try await task.value; Issue.record("Cancelled search succeeded") }
        catch is CancellationError { }
        #expect(try fixture.recordCount() == 0)
    }

    @Test("Requests survive cold start and busy transfers and are consumed once")
    func routing() throws {
        let router = HistorySearchRequests()
        try router.submit(" first ", mode: .keywords)
        #expect(router.consume(isBusy: true) == nil)
        #expect(router.pending?.query == "first")
        try router.submit("last month on GitHub", mode: .naturalLanguage)
        let request = try #require(router.consume(isBusy: false))
        #expect(request.mode == .naturalLanguage)
        #expect(request.query == "last month on GitHub")
        #expect(router.consume(isBusy: false) == nil)
        #expect(throws: HistorySearchError.self) { try router.submit(" ", mode: .keywords) }
        #expect(throws: HistorySearchError.self) { try router.submit(String(repeating: "x", count: 2_001), mode: .keywords) }
    }

}
