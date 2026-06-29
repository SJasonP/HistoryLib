import Foundation
import SwiftData

@Model
final class Item {
    // Indexed because nearly every browse, search, export, summary, and dedup
    // query sorts by `visitedAt` or looks records up by `uniqueKey`. Without
    // these indexes large datasets fall back to full-table scans.
    #Index<Item>([\.visitedAt], [\.uniqueKey])

    var uniqueKey: String = ""
    var url: String = ""
    var title: String = ""
    @Attribute(originalName: "timestamp") var visitedAt: Date = Date()
    var visitCount: Int = 1
    var sourceBrowser: String = "Safari"
    var sourceFileName: String = ""
    var rawTimeUsec: Int64 = 0
    var sourceURL: String?
    var sourceTimeUsec: Int64?
    var destinationURL: String?
    var destinationTimeUsec: Int64?
    var latestVisitWasHTTPGet: Bool?
    var importedAt: Date = Date()

    init(
        uniqueKey: String,
        url: String,
        title: String,
        visitedAt: Date,
        visitCount: Int,
        sourceBrowser: String,
        sourceFileName: String,
        rawTimeUsec: Int64,
        sourceURL: String? = nil,
        sourceTimeUsec: Int64? = nil,
        destinationURL: String? = nil,
        destinationTimeUsec: Int64? = nil,
        latestVisitWasHTTPGet: Bool? = nil,
        importedAt: Date = Date()
    ) {
        self.uniqueKey = uniqueKey
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
        self.visitCount = visitCount
        self.sourceBrowser = sourceBrowser
        self.sourceFileName = sourceFileName
        self.rawTimeUsec = rawTimeUsec
        self.sourceURL = sourceURL
        self.sourceTimeUsec = sourceTimeUsec
        self.destinationURL = destinationURL
        self.destinationTimeUsec = destinationTimeUsec
        self.latestVisitWasHTTPGet = latestVisitWasHTTPGet
        self.importedAt = importedAt
    }
}
