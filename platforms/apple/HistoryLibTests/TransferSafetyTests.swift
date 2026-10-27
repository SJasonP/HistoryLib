import Foundation
import SwiftData
import Testing
import ZIPFoundation
@testable import History_Lib

@Suite("Transfer security regressions")
@MainActor
struct TransferSafetyTests {
    @Test("Count overflow is safe for numeric/string imports, existing records and near duplicates")
    func importedCountsSaturate() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        let first = try fixture.writeSafariExportJSON(records: [
            .init(url: "https://counts.example/a", timeUsec: 1_710_000_000_000_000, title: "A", visitCount: Int.max),
            .init(url: "https://counts.example/a", timeUsec: 1_710_000_000_000_000, title: "B", visitCount: 1)
        ])
        let report = try await HistoryImporter().importFrom(url: first, modelContext: fixture.context)
        #expect(report.importedRecordCount == 1)
        #expect(report.skippedRecordCount == 1)
        #expect(try fixture.firstItem()?.visitCount == Int.max)
        let archive = try fixture.writeHistoryLibArchive(chunks: [[
            #"{"u":"https://counts.example/a","ts":1710000001000000,"vc":"9223372036854775807"}"#
        ]])
        let second = try await HistoryImporter().importFrom(url: archive, modelContext: fixture.context)
        #expect(second.skippedRecordCount == 1)
        #expect(try fixture.firstItem()?.visitCount == Int.max)
    }

    @Test("Persisted custom keys cannot overflow either cleanup addition")
    func cleanupCountsSaturate() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        for (index, count) in [Int.max, Int.max, 1].enumerated() {
            let archive = try fixture.writeHistoryLibArchive(chunks: [[
                "{\"u\":\"https://cleanup.example/\",\"ts\":1710000000000000,\"uk\":\"custom-\(index)\",\"vc\":\(count)}"
            ]])
            _ = try await HistoryImporter().importFrom(url: archive, modelContext: fixture.context)
        }
        #expect(try fixture.recordCount() == 3)
        let report = try await HistoryDuplicateCleaner().deduplicate(modelContainer: fixture.container)
        #expect(report.removedCount == 2)
        let refreshed = ModelContext(fixture.container)
        #expect(try refreshed.fetch(FetchDescriptor<Item>()).first?.visitCount == Int.max)
        #expect(HistoryVisitCount.adding(0, 5) == 5)
        #expect(HistoryVisitCount.adding(3, 5) == 8)
    }

    @Test("History-first Safari JSON and ZIP stream beyond the old sniff prefix")
    func safariMetadataLast() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        let records = (0..<1_100).map {
            "{\"url\":\"https://stream.example/\($0)\",\"time_usec\":\(1_710_000_000_000_000 + Int64($0) * 2_000_000),\"title\":\"{escaped \\\"quote\\\"}\"}"
        }.joined(separator: ",")
        let body = Data(("{\"ignored\":[true,null,1.2e-3],\"history\":[" + records +
            "],\"metadata\":{\"browser_name\":\"sAfArI\",\"data_type\":\"hIsToRy\"}}").utf8)
        #expect(body.count > 64 * 1024)
        let json = fixture.tempDirectoryURL.appendingPathComponent("History.json")
        try body.write(to: json)
        let report = try await HistoryImporter().importFrom(url: json, modelContext: fixture.context)
        #expect(report.importedRecordCount == 1_100)
        let zip = try fixture.writeZipWithEntry(path: "nested/History.json", contents: body)
        let target = try TestFixture()
        defer { target.cleanup() }
        let zipped = try await HistoryImporter().importFrom(url: zip, modelContext: target.context)
        #expect(zipped.format == .safari)
        #expect(zipped.importedRecordCount == 1_100)
    }

    @Test("Unknown highly compressible ZIP remains unrecognized without writes")
    func unknownCompressedJSON() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        let body = Data(("{\"unknown\":\"" + String(repeating: "x", count: 2 * HistoryTransferLimits.recordBytes) + "\"}").utf8)
        let zip = try fixture.writeZipWithEntry(path: "data.json", contents: body)
        #expect(try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize! < body.count / 20)
        await #expect(throws: HistoryImportError.self) {
            _ = try await HistoryImporter().importFrom(url: zip, modelContext: fixture.context)
        }
        #expect(try fixture.recordCount() == 0)
    }

    @Test("ZIP extraction enforces actual bytes even when the advertised size lies")
    func dishonestZIPSize() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        let zip = try fixture.writeZipWithEntry(path: "data.json", contents: Data(repeating: 120, count: 65_536))
        var bytes = try Data(contentsOf: zip)
        let signature = Data([0x50, 0x4B, 0x01, 0x02])
        let central = try #require(bytes.range(of: signature)?.lowerBound)
        bytes.replaceSubrange((central + 24)..<(central + 28), with: [8, 0, 0, 0])
        try bytes.write(to: zip)
        let destination = fixture.tempDirectoryURL.appendingPathComponent("extracted", isDirectory: true)
        #expect(throws: (any Error).self) { try ImportZipArchive.extractZip(at: zip, to: destination) }
        let output = destination.appendingPathComponent("data.json")
        #expect((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 <= 8)
    }

    @Test("Oversized Safari and Chrome records fail without an unbounded buffer")
    func oversizedExternalRecords() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        let largeTitle = String(repeating: "x", count: HistoryTransferLimits.recordBytes)
        let safari = try fixture.writeSafariExportJSON(records: [
            .init(url: "https://large.example/", timeUsec: 1_710_000_000_000_000, title: largeTitle)
        ])
        let result = try await HistoryImporter().importFrom(url: safari, modelContext: fixture.context)
        #expect(result.failures.count == 1)
        #expect(try fixture.recordCount() == 0)
        let chrome = try fixture.writeChromeTakeoutJSON(records: [
            TestFixture.chromeRecord(url: "https://large.example/", timeUsec: "1710000000000000", title: largeTitle)
        ])
        await #expect(throws: HistoryTransferError.resourceLimitExceeded) {
            _ = try await ChromeTakeoutStreamParser().parse(url: chrome) { _ in Issue.record("Oversized record escaped the reader") }
        }
        // Escapes and nested unknown values remain valid in ordinary records.
        let control = try fixture.writeChromeTakeoutJSON(records: [
            TestFixture.chromeRecord(url: "https://small.example/", timeUsec: "1710000000000000", title: "{quote: \" value}")
        ])
        var accepted = 0
        let malformed = try await ChromeTakeoutStreamParser().parse(url: control) { _ in accepted += 1 }
        #expect(accepted == 1 && malformed == 0)
    }

    @Test("Native line limits and malformed later chunks are checked before all writes")
    func nativeValidationPrecedesBatches() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        let valid = (0..<1_100).map { "{\"u\":\"https://native.example/\($0)\",\"ts\":1710000000000000}" }
        let large = "{\"u\":\"https://large.example/\",\"ts\":1710000000000000,\"t\":\"" +
            String(repeating: "x", count: HistoryTransferLimits.nativeRecordBytes) + "\"}"
        for invalid in [large, #"{"t":"missing required fields"}"#] {
            let archive = try fixture.writeHistoryLibArchive(chunks: [valid, [invalid]])
            await #expect(throws: (any Error).self) {
                _ = try await HistoryImporter().importFrom(url: archive, modelContext: fixture.context)
            }
            #expect(try fixture.recordCount() == 0)
        }
        let archive = try fixture.writeHistoryLibArchive(chunks: [valid + valid.map { $0.replacingOccurrences(of: "native.example", with: "second.example") }])
        let report = try await HistoryImporter().importFrom(url: archive, modelContext: fixture.context)
        #expect(report.importedRecordCount == 2_200)
    }

    @Test("A near-limit external record can be exported and imported with native metadata")
    func nearLimitRoundTrip() async throws {
        let source = try TestFixture()
        defer { source.cleanup() }
        let prefix = #"{"url":"https://limit.example/","time_usec":1710000000000000,"title":""#
        let suffix = #""}"#
        let title = String(repeating: "x", count: HistoryTransferLimits.recordBytes - prefix.utf8.count - suffix.utf8.count - 1)
        let record = prefix + title + suffix
        #expect(record.utf8.count == HistoryTransferLimits.recordBytes - 1)
        let json = source.tempDirectoryURL.appendingPathComponent("History.json")
        let body = #"{"metadata":{"browser_name":"Safari","data_type":"history"},"history":["# + record + "]}"
        try Data(body.utf8).write(to: json)
        let result = try await HistoryImporter().importFrom(url: json, modelContext: source.context)
        #expect(result.importedRecordCount == 1)
        let prepared = try await HistoryExporter().prepareExportFile(modelContext: source.context, format: .historyLib, split: .single)
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectoryURL) }
        let target = try TestFixture()
        defer { target.cleanup() }
        let imported = try await HistoryImporter().importFrom(url: prepared.fileURL, modelContext: target.context)
        #expect(imported.importedRecordCount == 1)
        #expect(try target.firstItem()?.title == title)
    }

    @Test("Leading whitespace is consumed by the reader actor, with cancellation")
    func readerPrefixCancellation() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        let url = fixture.tempDirectoryURL.appendingPathComponent("prefix.json")
        try Data((String(repeating: " ", count: 2 * 1_048_576) + #"{"history":[]}"#).utf8).write(to: url)
        let reader = try HistoryJSONArrayReader(url: url, arrayKey: "history")
        #expect(try await reader.nextValue() == nil)
        let cancelled = Task {
            let reader = try HistoryJSONArrayReader(url: url, arrayKey: "history")
            try Task.checkCancellation()
            return try await reader.nextValue()
        }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
    }

    @Test("Native imported timestamp integers survive extreme Date round trips")
    func importedTimestampRoundTrips() async throws {
        let source = try TestFixture()
        defer { source.cleanup() }
        let values: [Int64] = [Int64.max, Int64.min, 0, 1_710_000_000_000_001]
        let lines = values.enumerated().map { index, value in
            "{\"u\":\"https://timestamp.example/\(index)\",\"ts\":1710000000000000,\"ia\":\"\(value)\"}"
        }
        let archive = try source.writeHistoryLibArchive(chunks: [lines])
        _ = try await HistoryImporter().importFrom(url: archive, modelContext: source.context)
        let export = try await HistoryExporter().prepareExportFile(modelContext: source.context, format: .historyLib, split: .single)
        defer { try? FileManager.default.removeItem(at: export.cleanupDirectoryURL) }
        let target = try TestFixture()
        defer { target.cleanup() }
        _ = try await HistoryImporter().importFrom(url: export.fileURL, modelContext: target.context)
        let items = try target.context.fetch(FetchDescriptor<Item>()).sorted { $0.url < $1.url }
        #expect(items.map(\.rawImportedAtUsec) == values.map(Optional.some))
    }

    @Test("Legacy unsafe Dates return controlled errors and negative visit microseconds survive")
    func legacyTimestampSafety() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }
        try fixture.insertItem(url: "https://legacy.example/", title: "Legacy", visitedAt: Date(timeIntervalSince1970: 1_710_000_000), browser: "Safari", uniqueKey: "legacy")
        let item = try #require(try fixture.firstItem())
        item.importedAt = Date(timeIntervalSince1970: Double(Int64.max) / 1_000_000)
        #expect(throws: HistoryTransferError.invalidTimestamp) { _ = try HLRecord(from: item, tsUsec: item.rawTimeUsec) }
        for seconds in [Double.infinity, -Double.infinity, Double.nan] {
            #expect(throws: HistoryTransferError.invalidTimestamp) { _ = try HistoryTimestamp.microseconds(from: Date(timeIntervalSince1970: seconds)) }
        }
        item.rawTimeUsec = Int64.min
        #expect(try recordTimeUsec(from: item) == Int64.min)
        item.rawTimeUsec = 0
        item.visitedAt = Date(timeIntervalSince1970: Double(Int64.max) / 1_000_000)
        #expect(throws: HistoryTransferError.invalidTimestamp) { _ = try recordTimeUsec(from: item) }
    }
}

@Suite("Bounded favicon transport")
struct FaviconTransportTests {
    @Test("Response bodies obey limits without trusting Content-Length", arguments: ["exact", "oversize", "lying", "header", "status"])
    func responseLimits(scenario: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyntheticFaviconProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://favicon.example/\(scenario)")!)
        let data = await BoundedFaviconResponse.data(for: request, session: session, maximumBytes: 1_024)
        if scenario == "exact" { #expect(data?.count == 1_024) }
        else { #expect(data == nil) }
    }

    @Test("Cancelling a stalled response completes without retaining the request")
    func cancellation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyntheticFaviconProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://favicon.example/stalled?id=\(UUID().uuidString)")!
        let task = Task {
            await BoundedFaviconResponse.data(for: URLRequest(url: url), session: session, maximumBytes: 1_024)
        }
        for _ in 0..<200 {
            if SyntheticFaviconProtocol.requests.contains(url.absoluteString) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(SyntheticFaviconProtocol.requests.contains(url.absoluteString))
        task.cancel()
        #expect(await task.value == nil)
    }
}

private final class SyntheticRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var started: Set<String> = []
    func insert(_ url: String) { lock.lock(); defer { lock.unlock() }; started.insert(url) }
    func contains(_ url: String) -> Bool { lock.lock(); defer { lock.unlock() }; return started.contains(url) }
}

private final class SyntheticFaviconProtocol: URLProtocol, @unchecked Sendable {
    static let requests = SyntheticRequestState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "favicon.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let scenario = request.url!.lastPathComponent
        var headers: [String: String] = [:]
        if scenario == "lying" { headers["Content-Length"] = "1" }
        if scenario == "header" { headers["Content-Length"] = "99999" }
        let response = HTTPURLResponse(url: request.url!, statusCode: scenario == "status" ? 500 : 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 120, count: 512))
        if scenario == "stalled" {
            Self.requests.insert(request.url!.absoluteString)
            return
        }
        client?.urlProtocol(self, didLoad: Data(repeating: 120, count: 512))
        if scenario != "exact" { client?.urlProtocol(self, didLoad: Data([120])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
