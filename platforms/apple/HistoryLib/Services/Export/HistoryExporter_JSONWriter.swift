import Foundation

final class JSONHistoryFileWriter {
    private let fileHandle: FileHandle
    private let encoder = JSONEncoder()
    private let format: HistoryExportFormat
    private var hasWrittenRecord = false
    private var isFinished = false

    init(fileURL: URL, format: HistoryExportFormat, exportTime: Date) throws {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: fileURL)
        self.format = format
        try write(headerData(format: format, exportTime: exportTime))
    }

    func appendSafari(item: Item) throws {
        guard format == .safari, !isFinished else { return }

        if hasWrittenRecord {
            try write(Data(",".utf8))
        }

        let record = SafariExportRecord(from: item)
        try write(try encoder.encode(record))
        hasWrittenRecord = true
    }

    func finish() throws {
        guard !isFinished else { return }
        try write(Data("]}".utf8))
        try fileHandle.close()
        isFinished = true
    }

    deinit {
        if !isFinished {
            try? fileHandle.close()
        }
    }

    private func write(_ data: Data) throws {
        if #available(iOS 13.4, macOS 10.15.4, *) {
            try fileHandle.write(contentsOf: data)
        } else {
            fileHandle.write(data)
        }
    }

    private func headerData(format: HistoryExportFormat, exportTime: Date) -> Data {
        let exportTimeUsec = Int64((exportTime.timeIntervalSince1970 * 1_000_000).rounded())
        let header: String

        switch format {
        case .safari:
            header = "{\"metadata\":{\"browser_name\":\"Safari\",\"browser_version\":\"HistoryLib\",\"data_type\":\"history\",\"export_time_usec\":\(exportTimeUsec),\"schema_version\":1},\"history\":["
        case .historyLib:
            header = "{\"metadata\":{\"format\":\"historylib\",\"app\":\"HistoryLib\",\"data_type\":\"history\",\"export_time_usec\":\(exportTimeUsec),\"schema_version\":1},\"history\":["
        }

        return Data(header.utf8)
    }
}

private struct SafariExportRecord: Encodable {
    let url: String
    let timeUsec: Int64
    let visitCount: Int
    let title: String
    let sourceURL: String?
    let sourceTimeUsec: Int64?
    let destinationURL: String?
    let destinationTimeUsec: Int64?
    let latestVisitWasHTTPGet: Bool?

    init(from item: Item) {
        url = item.url
        timeUsec = recordTimeUsec(from: item)
        visitCount = max(item.visitCount, 1)
        title = item.title
        sourceURL = item.sourceURL
        sourceTimeUsec = item.sourceTimeUsec
        destinationURL = item.destinationURL
        destinationTimeUsec = item.destinationTimeUsec
        latestVisitWasHTTPGet = item.latestVisitWasHTTPGet
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case timeUsec = "time_usec"
        case visitCount = "visit_count"
        case title
        case sourceURL = "source_url"
        case sourceTimeUsec = "source_time_usec"
        case destinationURL = "destination_url"
        case destinationTimeUsec = "destination_time_usec"
        case latestVisitWasHTTPGet = "latest_visit_was_http_get"
    }
}
