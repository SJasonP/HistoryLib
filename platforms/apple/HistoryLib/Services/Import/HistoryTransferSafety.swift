import Foundation

enum HistoryTransferError: LocalizedError {
    case resourceLimitExceeded
    case invalidJSON
    case invalidTimestamp

    var errorDescription: String? {
        switch self {
        case .resourceLimitExceeded:
            String(localized: "A history record exceeds the safe processing limit.")
        case .invalidJSON:
            String(localized: "The history JSON file is incomplete or damaged.")
        case .invalidTimestamp:
            String(localized: "A stored timestamp cannot be exported safely.")
        }
    }
}

enum HistoryTransferLimits {
    // Bound a retained record, not the total number of records in a library.
    nonisolated static let recordBytes = 1_048_576
    // Native records include dedup keys and source metadata absent in external
    // inputs, and JSON escaping can expand decoded strings. Export checks this
    // same limit so a successfully written HLZ is always readable by this app.
    nonisolated static let nativeRecordBytes = 8 * 1_048_576
    nonisolated static let batchBytes = 4 * 1_048_576
}

enum HistoryVisitCount {
    /// Counts saturate at the storage type's maximum, including legacy/synced data.
    /// Zero is valid for a not-yet-populated cleanup accumulator.
    nonisolated static func adding(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = max(0, lhs).addingReportingOverflow(max(0, rhs))
        return overflow ? Int.max : sum
    }
}

enum HistoryTimestamp {
    static func microseconds(from date: Date) throws -> Int64 {
        let rounded = (date.timeIntervalSince1970 * 1_000_000).rounded()
        guard let value = Int64(exactly: rounded) else {
            throw HistoryTransferError.invalidTimestamp
        }
        return value
    }
}
