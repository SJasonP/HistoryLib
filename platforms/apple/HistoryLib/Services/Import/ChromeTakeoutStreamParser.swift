import Foundation

enum ChromeTakeoutStreamError: LocalizedError {
    case missingHistoryArray
    case truncatedJSON

    var errorDescription: String? {
        switch self {
        case .missingHistoryArray:
            return String(localized: "The file does not contain Chrome browser history.")
        case .truncatedJSON:
            return String(localized: "The Chrome browser history file is incomplete or damaged.")
        }
    }
}

struct ChromeTakeoutRecord: Decodable {
    let url: String?
    let title: String?
    let timeUsec: Int64?

    private enum CodingKeys: String, CodingKey {
        case url
        case title
        case timeUsec = "time_usec"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        timeUsec = container.decodeFlexibleInt64IfPresent(forKey: .timeUsec)
    }
}

/// One bounded JSON value is read on a background actor at a time.
struct ChromeTakeoutStreamParser {
    func parse(url: URL, onRecord: (ChromeTakeoutRecord) throws -> Void) async throws -> Int {
        let reader = try HistoryJSONArrayReader(url: url, arrayKey: "Browser History")
        var malformedRecordCount = 0
        var processed = 0
        do {
            while let data = try await reader.nextValue() {
                try Task.checkCancellation()
                if let record = try? JSONDecoder().decode(ChromeTakeoutRecord.self, from: data) {
                    try onRecord(record)
                } else {
                    malformedRecordCount += 1
                }
                processed += 1
                if processed.isMultiple(of: 64) { await Task.yield() }
            }
        } catch HistoryTransferError.invalidJSON {
            throw ChromeTakeoutStreamError.truncatedJSON
        }
        return malformedRecordCount
    }
}
