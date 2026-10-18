import Foundation
import SwiftData

struct SummaryTopSite: Codable, Hashable, Sendable {
    let host: String
    let visits: Int
}

@Model
final class SummarySnapshot {
    var generatedAt: Date = Date()
    var totalRecords: Int = 0
    var averagePerDay: Double = 0
    var averagePerMonth: Double = 0
    var averagePerYear: Double = 0
    var topSitesData: Data = Data()

    init(
        generatedAt: Date,
        totalRecords: Int,
        averagePerDay: Double,
        averagePerMonth: Double,
        averagePerYear: Double,
        topSites: [SummaryTopSite]
    ) {
        self.generatedAt = generatedAt
        self.totalRecords = totalRecords
        self.averagePerDay = averagePerDay
        self.averagePerMonth = averagePerMonth
        self.averagePerYear = averagePerYear
        self.topSitesData = (try? JSONEncoder().encode(topSites)) ?? Data()
    }

    var topSites: [SummaryTopSite] {
        (try? JSONDecoder().decode([SummaryTopSite].self, from: topSitesData)) ?? []
    }
}
