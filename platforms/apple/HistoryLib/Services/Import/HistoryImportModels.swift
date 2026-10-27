import Foundation
import UniformTypeIdentifiers

struct ImportFileFailure {
    let fileName: String
    let reason: String
}

struct ImportDedupOptions: Sendable {
    var enableNearDuplicateTolerance: Bool
    var nearDuplicateToleranceSeconds: Int64

    nonisolated init(
        enableNearDuplicateTolerance: Bool = true,
        nearDuplicateToleranceSeconds: Int64 = 1
    ) {
        self.enableNearDuplicateTolerance = enableNearDuplicateTolerance
        self.nearDuplicateToleranceSeconds = nearDuplicateToleranceSeconds
    }
}

enum HistoryImportFormatResolved: String {
    case safari
    case chrome
    case historyLib

    var title: String {
        switch self {
        case .safari:
            return "Safari"
        case .chrome:
            return "Chrome"
        case .historyLib:
            return "HistoryLib"
        }
    }
}

enum HistoryImportError: LocalizedError {
    case unrecognizedFormat

    var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            return String(localized: "The selected item is not a recognized Safari history export, Chrome Takeout export, or HistoryLib archive.")
        }
    }
}

struct HistoryImportReport {
    let format: HistoryImportFormatResolved
    let scannedFileCount: Int
    let validFileCount: Int
    let importedRecordCount: Int
    let skippedRecordCount: Int
    let failures: [ImportFileFailure]
}

/// Progress for a running import. `fraction` is nil when the total is not yet
/// known (shown as an indeterminate bar).
struct HistoryImportProgress {
    let fraction: Double?
    let message: String
    let importedRecordCount: Int
    let skippedRecordCount: Int

    init(
        fraction: Double?,
        message: String,
        importedRecordCount: Int = 0,
        skippedRecordCount: Int = 0
    ) {
        self.fraction = fraction
        self.message = message
        self.importedRecordCount = importedRecordCount
        self.skippedRecordCount = skippedRecordCount
    }
}

typealias HistoryImportProgressHandler = (HistoryImportProgress) -> Void

extension UTType {
    static var historyLibArchive: UTType {
        UTType(filenameExtension: "hlz")
            ?? UTType(exportedAs: "com.sjasonp.historylib.archive")
    }
}
