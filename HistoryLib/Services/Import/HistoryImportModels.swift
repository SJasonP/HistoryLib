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

enum HistoryImportFormatPreference: String, CaseIterable, Identifiable {
    case automatic
    case safari
    case historyLib

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return String(localized: "Auto Detect")
        case .safari:
            return String(localized: "Safari Export")
        case .historyLib:
            return String(localized: "HistoryLib Archive (.hlz)")
        }
    }
}

enum HistoryImportFormatResolved: String {
    case safari
    case historyLib

    var title: String {
        switch self {
        case .safari:
            return "Safari"
        case .historyLib:
            return "HistoryLib"
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
}

typealias HistoryImportProgressHandler = (HistoryImportProgress) -> Void

extension UTType {
    static var historyLibArchive: UTType {
        UTType(filenameExtension: "hlz")
            ?? UTType(exportedAs: "com.sjasonp.historylib.archive")
    }
}
