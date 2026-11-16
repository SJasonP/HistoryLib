import Foundation
import SwiftData

struct SummaryTopSite: Codable, Hashable, Sendable {
    let host: String
    let visits: Int
}

struct SummaryBrowser: Codable, Hashable, Sendable, Identifiable {
    let browser: String
    let visits: Int

    var id: String { browser }
}

struct SummaryMonth: Codable, Hashable, Sendable, Identifiable {
    let month: String
    let visits: Int

    var id: String { month }
}

@Model
final class SummarySnapshot {
    var generatedAt: Date = Date()
    var generatedBuildVersion: String = ""
    var totalRecords: Int = 0
    var averagePerDay: Double = 0
    var averagePerMonth: Double = 0
    var averagePerYear: Double = 0
    var averagePerActiveDay: Double = 0
    var activeDays: Int = 0
    var totalVisits: Int = 0
    var uniqueDomains: Int = 0
    var oldestVisitedAt: Date?
    var newestVisitedAt: Date?
    var topSitesData: Data = Data()
    var browserBreakdownData: Data = Data()
    var monthlyTrendData: Data = Data()

    init(
        generatedAt: Date,
        generatedBuildVersion: String = "",
        totalRecords: Int,
        averagePerDay: Double,
        averagePerMonth: Double,
        averagePerYear: Double,
        averagePerActiveDay: Double = 0,
        activeDays: Int = 0,
        totalVisits: Int = 0,
        uniqueDomains: Int = 0,
        oldestVisitedAt: Date? = nil,
        newestVisitedAt: Date? = nil,
        topSites: [SummaryTopSite],
        browserBreakdown: [SummaryBrowser] = [],
        monthlyTrend: [SummaryMonth] = []
    ) {
        self.generatedAt = generatedAt
        self.generatedBuildVersion = generatedBuildVersion
        self.totalRecords = totalRecords
        self.averagePerDay = averagePerDay
        self.averagePerMonth = averagePerMonth
        self.averagePerYear = averagePerYear
        self.averagePerActiveDay = averagePerActiveDay
        self.activeDays = activeDays
        self.totalVisits = totalVisits
        self.uniqueDomains = uniqueDomains
        self.oldestVisitedAt = oldestVisitedAt
        self.newestVisitedAt = newestVisitedAt
        self.topSitesData = (try? JSONEncoder().encode(topSites)) ?? Data()
        self.browserBreakdownData = (try? JSONEncoder().encode(browserBreakdown)) ?? Data()
        self.monthlyTrendData = (try? JSONEncoder().encode(monthlyTrend)) ?? Data()
    }

    var topSites: [SummaryTopSite] {
        (try? JSONDecoder().decode([SummaryTopSite].self, from: topSitesData)) ?? []
    }

    var browserBreakdown: [SummaryBrowser] {
        (try? JSONDecoder().decode([SummaryBrowser].self, from: browserBreakdownData)) ?? []
    }

    var monthlyTrend: [SummaryMonth] {
        (try? JSONDecoder().decode([SummaryMonth].self, from: monthlyTrendData)) ?? []
    }
}
