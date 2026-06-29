import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum HistoryExportFormat: String, CaseIterable, Identifiable {
    case historyLib
    case safari

    var id: String { rawValue }

    var title: String {
        switch self {
        case .historyLib:
            return "HistoryLib"
        case .safari:
            return "Safari"
        }
    }

    var filePrefix: String {
        switch self {
        case .historyLib:
            return "historylib"
        case .safari:
            return "safari"
        }
    }
}

enum HistoryExportSplit: String, CaseIterable, Identifiable {
    case single
    case year
    case month
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            return String(localized: "Single File")
        case .year:
            return String(localized: "One File Per Year")
        case .month:
            return String(localized: "One File Per Month")
        case .day:
            return String(localized: "One File Per Day")
        }
    }

    var token: String {
        switch self {
        case .single:
            return "single"
        case .year:
            return "yearly"
        case .month:
            return "monthly"
        case .day:
            return "daily"
        }
    }
}

struct PreparedExportFile {
    let fileURL: URL
    let contentType: UTType
    let defaultFilename: String
    let cleanupDirectoryURL: URL
}

struct HistoryExportProgress {
    enum Phase {
        case preparing
        case exporting
        case packaging
    }

    let phase: Phase
    let fraction: Double
    let message: String
}

struct ExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json, .zip, .data]

    let sourceFileURL: URL

    init(sourceFileURL: URL) {
        self.sourceFileURL = sourceFileURL
    }

    init(configuration: ReadConfiguration) throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryLibImportedExportDocument", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let targetURL = tempRoot.appendingPathComponent("document.data")
        let data = configuration.file.regularFileContents ?? Data()
        try data.write(to: targetURL, options: .atomic)
        sourceFileURL = targetURL
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: sourceFileURL, options: .immediate)
    }
}
