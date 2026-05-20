import Foundation

struct HLRecord: Encodable {
    let u: String
    let ts: Int64
    let t: String?
    let vc: Int?
    let uk: String?
    let sb: String?
    let ia: Int64?
    let rt: Int64?
    let sf: String?
    let su: String?
    let st: Int64?
    let du: String?
    let dt: Int64?
    let hg: Bool?

    init(from item: Item, tsUsec: Int64) {
        u = item.url
        ts = tsUsec
        t = item.title.isEmpty ? nil : item.title
        vc = item.visitCount > 0 ? item.visitCount : nil
        uk = item.uniqueKey.isEmpty ? nil : item.uniqueKey
        sb = item.sourceBrowser.isEmpty ? nil : item.sourceBrowser
        ia = Int64((item.importedAt.timeIntervalSince1970 * 1_000_000).rounded())
        rt = item.rawTimeUsec > 0 ? item.rawTimeUsec : nil
        sf = item.sourceFileName.isEmpty ? nil : item.sourceFileName
        su = item.sourceURL
        st = item.sourceTimeUsec
        du = item.destinationURL
        dt = item.destinationTimeUsec
        hg = item.latestVisitWasHTTPGet
    }
}

struct HLManifest: Encodable {
    let format: String
    let formatVersion: Int
    let createdAtUsec: Int64
    let appName: String
    let appVersion: String
    let recordSchema: String
    let recordCount: Int
    let chunkCount: Int
    let timeRangeUsec: HLTimeRangeUsec
    let chunkEncoding: String
    let chunkTargetRecords: Int
    let featureFlags: [String]
    let indexes: HLManifestIndexes
    let summary: String?

    private enum CodingKeys: String, CodingKey {
        case format
        case formatVersion = "format_version"
        case createdAtUsec = "created_at_usec"
        case appName = "app_name"
        case appVersion = "app_version"
        case recordSchema = "record_schema"
        case recordCount = "record_count"
        case chunkCount = "chunk_count"
        case timeRangeUsec = "time_range_usec"
        case chunkEncoding = "chunk_encoding"
        case chunkTargetRecords = "chunk_target_records"
        case featureFlags = "feature_flags"
        case indexes
        case summary
    }
}

struct HLTimeRangeUsec: Encodable {
    let min: Int64
    let max: Int64
}

struct HLManifestIndexes: Encodable {
    let chunks: String
    let years: String
    let months: String
    let days: String
}

struct HLChunkIndexEntry: Encodable {
    let id: Int
    let path: String
    let recordCount: Int
    let minTs: Int64
    let maxTs: Int64
    let sha256: String

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case recordCount = "record_count"
        case minTs = "min_ts"
        case maxTs = "max_ts"
        case sha256
    }
}

struct HLYearIndexEntry: Encodable {
    let year: Int
    let recordCount: Int
    let minTs: Int64
    let maxTs: Int64

    private enum CodingKeys: String, CodingKey {
        case year
        case recordCount = "record_count"
        case minTs = "min_ts"
        case maxTs = "max_ts"
    }
}

struct HLMonthIndexEntry: Encodable {
    let month: String
    let recordCount: Int
    let minTs: Int64
    let maxTs: Int64

    private enum CodingKeys: String, CodingKey {
        case month
        case recordCount = "record_count"
        case minTs = "min_ts"
        case maxTs = "max_ts"
    }
}

struct HLDayIndexEntry: Encodable {
    let day: String
    let recordCount: Int
    let minTs: Int64
    let maxTs: Int64

    private enum CodingKeys: String, CodingKey {
        case day
        case recordCount = "record_count"
        case minTs = "min_ts"
        case maxTs = "max_ts"
    }
}

struct HLSummarySnapshotPayload: Encodable {
    let generatedAtUsec: Int64
    let totalRecords: Int
    let averagePerDay: Double
    let averagePerMonth: Double
    let averagePerYear: Double
    let topSites: [SummaryTopSite]

    init(from snapshot: SummarySnapshot) {
        generatedAtUsec = Int64((snapshot.generatedAt.timeIntervalSince1970 * 1_000_000).rounded())
        totalRecords = snapshot.totalRecords
        averagePerDay = snapshot.averagePerDay
        averagePerMonth = snapshot.averagePerMonth
        averagePerYear = snapshot.averagePerYear
        topSites = snapshot.topSites
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAtUsec = "generated_at_usec"
        case totalRecords = "total_records"
        case averagePerDay = "average_per_day"
        case averagePerMonth = "average_per_month"
        case averagePerYear = "average_per_year"
        case topSites = "top_sites"
    }
}

struct TimeBucketStats {
    var count = 0
    var minTs: Int64 = .max
    var maxTs: Int64 = .min

    mutating func add(_ ts: Int64) {
        count += 1
        if ts < minTs {
            minTs = ts
        }
        if ts > maxTs {
            maxTs = ts
        }
    }
}

func recordTimeUsec(from item: Item) -> Int64 {
    if item.rawTimeUsec > 0 {
        return item.rawTimeUsec
    }
    return Int64((item.visitedAt.timeIntervalSince1970 * 1_000_000).rounded())
}
