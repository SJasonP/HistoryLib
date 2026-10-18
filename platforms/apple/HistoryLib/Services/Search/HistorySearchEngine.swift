import Foundation
import SwiftData

@MainActor
enum HistorySearchEngine {
    struct Page {
        let records: [Item]
        let nextOffset: Int
        let hasMore: Bool
    }

    static func page(
        in context: ModelContext, filter: HistorySearchFilter, offset: Int,
        scanLimit: Int = 1_000, targetMatches: Int = 300
    ) async throws -> Page {
        let filter = try filter.validated()
        guard scanLimit > 0, targetMatches > 0, offset >= 0 else { throw HistorySearchError.invalidCriteria }
        var cursor = offset
        var records: [Item] = []
        while true {
            try Task.checkCancellation()
            var descriptor = descriptor(for: filter)
            descriptor.fetchLimit = scanLimit
            descriptor.fetchOffset = cursor
            let scanned = try context.fetch(descriptor)
            cursor += scanned.count
            records.append(contentsOf: scanned.filter {
                filter.matches(url: $0.url, title: $0.title, browser: $0.sourceBrowser, visitedAt: $0.visitedAt)
            })
            // Keep the entire chunk: dropping its last matches would lose them
            // when the next page starts at the new cursor.
            if scanned.count < scanLimit {
                return Page(records: records, nextOffset: cursor, hasMore: false)
            }
            if records.count >= targetMatches {
                return Page(records: records, nextOffset: cursor, hasMore: true)
            }
            await Task.yield()
        }
    }

    private static func descriptor(for filter: HistorySearchFilter) -> FetchDescriptor<Item> {
        let predicate: Predicate<Item>?
        switch (filter.startDate, filter.endDate) {
        case let (.some(start), .some(end)):
            predicate = #Predicate { $0.visitedAt >= start && $0.visitedAt < end }
        case let (.some(start), .none):
            predicate = #Predicate { $0.visitedAt >= start }
        case let (.none, .some(end)):
            predicate = #Predicate { $0.visitedAt < end }
        case (.none, .none):
            predicate = nil
        }
        return FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\Item.visitedAt, order: .reverse), SortDescriptor(\Item.uniqueKey)]
        )
    }
}
