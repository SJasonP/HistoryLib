import CryptoKit
import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
import ZIPFoundation
@testable import History_Lib

@Suite("History Data Path Tests")
@MainActor
struct HistoryLibTests {
    @Test("Safari import applies strict dedup for exact duplicates")
    func safariImportStrictDedup() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let sharedTimeUsec: Int64 = 1_710_000_000_000_000
        let jsonURL = try fixture.writeSafariExportJSON(
            records: [
                .init(url: "https://example.com/a", timeUsec: sharedTimeUsec, title: "A"),
                .init(url: "https://example.com/a", timeUsec: sharedTimeUsec, title: "A duplicate"),
                .init(url: "https://example.com/b", timeUsec: sharedTimeUsec + 5_000_000, title: "B")
            ]
        )

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: jsonURL,
            modelContext: fixture.context,
            dedupOptions: ImportDedupOptions(enableNearDuplicateTolerance: false, nearDuplicateToleranceSeconds: 0)
        )

        #expect(report.importedRecordCount == 2)
        #expect(report.skippedRecordCount == 1)
        #expect(try fixture.recordCount() == 2)
    }

    @Test("Safari import near-duplicate tolerance is enabled by default")
    func safariImportNearDuplicateDefaultEnabled() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let firstURL = try fixture.writeSafariExportJSON(
            records: [
                .init(url: "https://example.com/near", timeUsec: 1_710_000_000_000_000, title: "Near 1")
            ]
        )
        let secondURL = try fixture.writeSafariExportJSON(
            records: [
                .init(url: "https://example.com/near", timeUsec: 1_710_000_001_000_000, title: "Near 2")
            ]
        )

        let importer = HistoryImporter()
        _ = try await importer.importFrom(url: firstURL, modelContext: fixture.context)
        let secondReport = try await importer.importFrom(url: secondURL, modelContext: fixture.context)

        #expect(secondReport.importedRecordCount == 0)
        #expect(secondReport.skippedRecordCount == 1)
        #expect(try fixture.recordCount() == 1)
    }

    @Test("Smart import rejects an unrecognized JSON file")
    func smartImportRejectsUnknownJSON() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let unknownURL = fixture.tempDirectoryURL.appendingPathComponent("unknown.json")
        try Data("{\"items\":[1,2,3]}".utf8).write(to: unknownURL)

        let importer = HistoryImporter()
        await #expect(throws: HistoryImportError.self) {
            _ = try await importer.importFrom(url: unknownURL, modelContext: fixture.context)
        }
        #expect(try fixture.recordCount() == 0)
    }

    @Test("Smart import rejects an unrecognized ZIP archive")
    func smartImportRejectsUnknownZIP() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let unknownURL = try fixture.writeZipWithEntry(
            path: "data.json",
            contents: Data("{\"items\":[1,2,3]}".utf8)
        )

        let importer = HistoryImporter()
        await #expect(throws: HistoryImportError.self) {
            _ = try await importer.importFrom(url: unknownURL, modelContext: fixture.context)
        }
        #expect(try fixture.recordCount() == 0)
    }

    @Test("HistoryLib export can be imported back without record loss")
    func historyLibRoundTripExportImport() async throws {
        let source = try TestFixture()
        defer { source.cleanup() }

        try source.insertItem(
            url: "https://alpha.example/path",
            title: "Alpha",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "alpha-key"
        )
        try source.insertItem(
            url: "https://beta.example/path",
            title: "Beta",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_100),
            browser: "Safari",
            uniqueKey: "beta-key"
        )
        try source.insertItem(
            url: "https://gamma.example/path",
            title: "Gamma",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_200),
            browser: "Safari",
            uniqueKey: "gamma-key"
        )

        let exporter = HistoryExporter()
        let prepared = try await exporter.prepareExportFile(
            modelContext: source.context,
            format: .historyLib,
            split: .single,
            password: ""
        )
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectoryURL) }

        #expect(prepared.fileURL.pathExtension.lowercased() == "hlz")
        #expect(FileManager.default.fileExists(atPath: prepared.fileURL.path))
        #expect(!HistoryLibEncryptedArchive.isEncryptedArchive(prepared.fileURL))

        let target = try TestFixture()
        defer { target.cleanup() }

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: prepared.fileURL,
            modelContext: target.context
        )

        #expect(report.format == .historyLib)
        #expect(report.importedRecordCount == 3)
        #expect(try target.recordCount() == 3)
    }

    @Test("Password-protected HistoryLib export imports only with the correct password")
    func encryptedHistoryLibRoundTripRequiresPassword() async throws {
        let source = try TestFixture()
        defer { source.cleanup() }
        try source.insertItem(
            url: "https://private.example/path",
            title: "Private",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "private-key"
        )

        let prepared = try await HistoryExporter().prepareExportFile(
            modelContext: source.context,
            format: .historyLib,
            split: .single,
            password: "correct horse battery staple"
        )
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectoryURL) }
        #expect(HistoryLibEncryptedArchive.isEncryptedArchive(prepared.fileURL))

        let target = try TestFixture()
        defer { target.cleanup() }
        let importer = HistoryImporter()

        await #expect(throws: HistoryLibEncryptedArchiveError.self) {
            _ = try await importer.importFrom(url: prepared.fileURL, modelContext: target.context)
        }
        await #expect(throws: HistoryLibEncryptedArchiveError.self) {
            _ = try await importer.importFrom(
                url: prepared.fileURL,
                modelContext: target.context,
                password: "wrong password"
            )
        }
        #expect(try target.recordCount() == 0)

        let report = try await importer.importFrom(
            url: prepared.fileURL,
            modelContext: target.context,
            password: "correct horse battery staple"
        )
        #expect(report.format == .historyLib)
        #expect(report.importedRecordCount == 1)
        #expect(try target.recordCount() == 1)
    }

    @Test("Encrypted archive uses randomized ciphertext and rejects tampering")
    func encryptedArchiveAuthenticatesTheWholeStream() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let plaintext = Data((0..<(HistoryLibEncryptedArchive.chunkSize + 257)).map { UInt8($0 % 251) })
        let sourceURL = fixture.tempDirectoryURL.appendingPathComponent("source.hlz")
        let firstURL = fixture.tempDirectoryURL.appendingPathComponent("first.hlz")
        let secondURL = fixture.tempDirectoryURL.appendingPathComponent("second.hlz")
        let decryptedURL = fixture.tempDirectoryURL.appendingPathComponent("decrypted.hlz")
        try plaintext.write(to: sourceURL)

        try HistoryLibEncryptedArchive.encrypt(
            sourceURL: sourceURL,
            destinationURL: firstURL,
            password: "stream authentication password"
        )
        try HistoryLibEncryptedArchive.encrypt(
            sourceURL: sourceURL,
            destinationURL: secondURL,
            password: "stream authentication password"
        )
        #expect(try Data(contentsOf: firstURL) != Data(contentsOf: secondURL))

        try HistoryLibEncryptedArchive.decrypt(
            sourceURL: firstURL,
            destinationURL: decryptedURL,
            password: "stream authentication password"
        )
        #expect(try Data(contentsOf: decryptedURL) == plaintext)

        var tampered = try Data(contentsOf: firstURL)
        tampered[tampered.count - 1] ^= 0x01
        let tamperedURL = fixture.tempDirectoryURL.appendingPathComponent("tampered.hlz")
        try tampered.write(to: tamperedURL)
        #expect(throws: HistoryLibEncryptedArchiveError.self) {
            try HistoryLibEncryptedArchive.decrypt(
                sourceURL: tamperedURL,
                destinationURL: decryptedURL,
                password: "stream authentication password"
            )
        }

        let truncatedURL = fixture.tempDirectoryURL.appendingPathComponent("truncated.hlz")
        let truncated = try Data(contentsOf: firstURL).dropLast(32)
        try Data(truncated).write(to: truncatedURL)
        #expect(throws: HistoryLibEncryptedArchiveError.self) {
            try HistoryLibEncryptedArchive.decrypt(
                sourceURL: truncatedURL,
                destinationURL: decryptedURL,
                password: "stream authentication password"
            )
        }

        var trailing = try Data(contentsOf: firstURL)
        trailing.append(0x00)
        let trailingURL = fixture.tempDirectoryURL.appendingPathComponent("trailing.hlz")
        try trailing.write(to: trailingURL)
        #expect(throws: HistoryLibEncryptedArchiveError.self) {
            try HistoryLibEncryptedArchive.decrypt(
                sourceURL: trailingURL,
                destinationURL: decryptedURL,
                password: "stream authentication password"
            )
        }
    }

    @Test("Encrypted archive rejects unsafe header parameters before key derivation")
    func encryptedArchiveRejectsUnsafeHeaderParameters() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let sourceURL = fixture.tempDirectoryURL.appendingPathComponent("source.hlz")
        let encryptedURL = fixture.tempDirectoryURL.appendingPathComponent("encrypted.hlz")
        let maliciousURL = fixture.tempDirectoryURL.appendingPathComponent("malicious.hlz")
        let decryptedURL = fixture.tempDirectoryURL.appendingPathComponent("decrypted.hlz")
        try Data("header bounds".utf8).write(to: sourceURL)
        try HistoryLibEncryptedArchive.encrypt(
            sourceURL: sourceURL,
            destinationURL: encryptedURL,
            password: "header validation password"
        )

        var malicious = try Data(contentsOf: encryptedURL)
        malicious.replaceSubrange(14..<22, with: repeatElement(UInt8.max, count: 8))
        try malicious.write(to: maliciousURL)

        do {
            try HistoryLibEncryptedArchive.decrypt(
                sourceURL: maliciousURL,
                destinationURL: decryptedURL,
                password: "header validation password"
            )
            Issue.record("Expected invalid header parameters to be rejected")
        } catch HistoryLibEncryptedArchiveError.invalidParameters {
            #expect(!FileManager.default.fileExists(atPath: decryptedURL.path))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Encrypted archive rejects reordered, duplicated, and unterminated frames")
    func encryptedArchiveRejectsInvalidFrameSequences() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let sourceURL = fixture.tempDirectoryURL.appendingPathComponent("source.hlz")
        let encryptedURL = fixture.tempDirectoryURL.appendingPathComponent("encrypted.hlz")
        let decryptedURL = fixture.tempDirectoryURL.appendingPathComponent("decrypted.hlz")
        let password = "frame sequence password"
        let plaintext = Data(repeating: 0x5A, count: HistoryLibEncryptedArchive.chunkSize + 1)
        try plaintext.write(to: sourceURL)
        try HistoryLibEncryptedArchive.encrypt(
            sourceURL: sourceURL,
            destinationURL: encryptedURL,
            password: password
        )

        let archive = try Data(contentsOf: encryptedURL)
        let headerSize = 66
        func frameRange(startingAt offset: Int) throws -> Range<Int> {
            guard archive.count >= offset + 4 else {
                throw HistoryLibEncryptedArchiveError.authenticationFailed
            }
            let length = archive[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let end = offset + 4 + Int(length)
            guard end <= archive.count else {
                throw HistoryLibEncryptedArchiveError.authenticationFailed
            }
            return offset..<end
        }

        let firstRange = try frameRange(startingAt: headerSize)
        let secondRange = try frameRange(startingAt: firstRange.upperBound)
        #expect(secondRange.upperBound == archive.count)

        var reordered = Data(archive[..<headerSize])
        reordered.append(archive[secondRange])
        reordered.append(archive[firstRange])

        var duplicated = Data(archive[..<headerSize])
        duplicated.append(archive[firstRange])
        duplicated.append(archive[firstRange])
        duplicated.append(archive[secondRange])

        let unterminated = Data(archive[..<firstRange.upperBound])
        for (name, malformed) in [
            ("reordered", reordered),
            ("duplicated", duplicated),
            ("unterminated", unterminated)
        ] {
            let malformedURL = fixture.tempDirectoryURL.appendingPathComponent("\(name).hlz")
            try malformed.write(to: malformedURL)
            #expect(throws: HistoryLibEncryptedArchiveError.self) {
                try HistoryLibEncryptedArchive.decrypt(
                    sourceURL: malformedURL,
                    destinationURL: decryptedURL,
                    password: password
                )
            }
        }
    }

    @Test("NFC-equivalent passwords open the same encrypted archive")
    func encryptedArchiveNormalizesUnicodePasswords() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let sourceURL = fixture.tempDirectoryURL.appendingPathComponent("source.hlz")
        let encryptedURL = fixture.tempDirectoryURL.appendingPathComponent("encrypted.hlz")
        let decryptedURL = fixture.tempDirectoryURL.appendingPathComponent("decrypted.hlz")
        let plaintext = Data("unicode password".utf8)
        try plaintext.write(to: sourceURL)

        try HistoryLibEncryptedArchive.encrypt(
            sourceURL: sourceURL,
            destinationURL: encryptedURL,
            password: "Cafe\u{0301} archive password"
        )
        try HistoryLibEncryptedArchive.decrypt(
            sourceURL: encryptedURL,
            destinationURL: decryptedURL,
            password: "Caf\u{00E9} archive password"
        )
        #expect(try Data(contentsOf: decryptedURL) == plaintext)
    }

    @Test("Safari single-file export is packaged as zip and can be imported back")
    func safariSingleZipRoundTripExportImport() async throws {
        let source = try TestFixture()
        defer { source.cleanup() }

        try source.insertItem(
            url: "https://single.example",
            title: "Single",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "single"
        )

        let exporter = HistoryExporter()
        let prepared = try await exporter.prepareExportFile(
            modelContext: source.context,
            format: .safari,
            split: .single
        )
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectoryURL) }

        #expect(prepared.fileURL.pathExtension.lowercased() == "zip")
        #expect(prepared.contentType == .zip)
        #expect(FileManager.default.fileExists(atPath: prepared.fileURL.path))

        let target = try TestFixture()
        defer { target.cleanup() }

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: prepared.fileURL,
            modelContext: target.context
        )

        #expect(report.importedRecordCount == 1)
        #expect(try target.recordCount() == 1)
    }

    @Test("Safari day-split zip export can be imported back")
    func safariZipRoundTripExportImport() async throws {
        let source = try TestFixture()
        defer { source.cleanup() }

        try source.insertItem(
            url: "https://one.example",
            title: "One",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "one"
        )
        try source.insertItem(
            url: "https://two.example",
            title: "Two",
            visitedAt: Date(timeIntervalSince1970: 1_710_086_400),
            browser: "Safari",
            uniqueKey: "two"
        )

        let exporter = HistoryExporter()
        let prepared = try await exporter.prepareExportFile(
            modelContext: source.context,
            format: .safari,
            split: .day
        )
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectoryURL) }

        #expect(prepared.fileURL.pathExtension.lowercased() == "zip")
        #expect(FileManager.default.fileExists(atPath: prepared.fileURL.path))

        let target = try TestFixture()
        defer { target.cleanup() }

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: prepared.fileURL,
            modelContext: target.context
        )

        #expect(report.importedRecordCount == 2)
        #expect(try target.recordCount() == 2)
    }

    @Test("Background duplicate cleaner removes near duplicates")
    func duplicateCleanerRemovesNearDuplicates() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        try fixture.insertItem(
            url: "https://cleaner.example",
            title: "A",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "a"
        )
        try fixture.insertItem(
            url: "https://cleaner.example",
            title: "B",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_001),
            browser: "Safari",
            uniqueKey: "b"
        )
        try fixture.insertItem(
            url: "https://cleaner.example",
            title: "C",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_003),
            browser: "Safari",
            uniqueKey: "c"
        )

        let cleaner = HistoryDuplicateCleaner()
        let report = try await cleaner.deduplicate(
            modelContainer: fixture.container,
            dedupOptions: ImportDedupOptions(enableNearDuplicateTolerance: true, nearDuplicateToleranceSeconds: 1)
        )

        #expect(report.removedCount == 1)
        #expect(try fixture.recordCount() == 2)
    }

    @Test("Import merges visit counts for exact duplicates instead of discarding them")
    func importMergesVisitCounts() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let sharedTimeUsec: Int64 = 1_710_000_000_000_000
        let jsonURL = try fixture.writeSafariExportJSON(
            records: [
                .init(url: "https://merge.example/a", timeUsec: sharedTimeUsec, title: "A", visitCount: 3),
                .init(url: "https://merge.example/a", timeUsec: sharedTimeUsec, title: "A again", visitCount: 5)
            ]
        )

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: jsonURL,
            modelContext: fixture.context,
            dedupOptions: ImportDedupOptions(enableNearDuplicateTolerance: false, nearDuplicateToleranceSeconds: 0)
        )

        #expect(report.importedRecordCount == 1)
        #expect(report.skippedRecordCount == 1)
        #expect(try fixture.recordCount() == 1)
        #expect(try fixture.firstItem()?.visitCount == 8)
    }

    @Test("Duplicate cleaner merges visit counts into the kept record")
    func duplicateCleanerMergesVisitCounts() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        try fixture.insertItem(
            url: "https://mergeclean.example",
            title: "A",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_000),
            browser: "Safari",
            uniqueKey: "a",
            visitCount: 2
        )
        try fixture.insertItem(
            url: "https://mergeclean.example",
            title: "B",
            visitedAt: Date(timeIntervalSince1970: 1_710_000_001),
            browser: "Safari",
            uniqueKey: "b",
            visitCount: 4
        )

        let cleaner = HistoryDuplicateCleaner()
        let report = try await cleaner.deduplicate(
            modelContainer: fixture.container,
            dedupOptions: ImportDedupOptions(enableNearDuplicateTolerance: true, nearDuplicateToleranceSeconds: 1)
        )

        #expect(report.removedCount == 1)
        #expect(try fixture.recordCount() == 1)
        #expect(try fixture.firstItem()?.visitCount == 6)
    }

    @Test("HistoryLib import accepts a valid empty archive")
    func historyLibImportAcceptsEmptyArchive() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let archiveRoot = try fixture.writeHistoryLibArchive(chunks: [])

        let importer = HistoryImporter()
        let report = try await importer.importFrom(
            url: archiveRoot,
            modelContext: fixture.context
        )

        #expect(report.importedRecordCount == 0)
        #expect(try fixture.recordCount() == 0)
    }

    @Test("HistoryLib import rejects a chunk whose checksum does not match")
    func historyLibImportRejectsChecksumMismatch() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let archiveRoot = try fixture.writeHistoryLibArchive(
            chunks: [["{\"u\":\"https://a.example\",\"ts\":1710000000000000}"]],
            corruptShaForChunkID: 1
        )

        let importer = HistoryImporter()
        await #expect(throws: (any Error).self) {
            _ = try await importer.importFrom(
                url: archiveRoot,
                modelContext: fixture.context
            )
        }
        #expect(try fixture.recordCount() == 0)
    }

    @Test("HistoryLib import rejects a record_count that does not match the chunks")
    func historyLibImportRejectsRecordCountMismatch() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let archiveRoot = try fixture.writeHistoryLibArchive(
            chunks: [["{\"u\":\"https://a.example\",\"ts\":1710000000000000}"]],
            manifestRecordCountOverride: 99
        )

        let importer = HistoryImporter()
        await #expect(throws: (any Error).self) {
            _ = try await importer.importFrom(
                url: archiveRoot,
                modelContext: fixture.context
            )
        }
        #expect(try fixture.recordCount() == 0)
    }

    @Test("HistoryLib import rejects a malformed chunk record")
    func historyLibImportRejectsMalformedRecord() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        // Valid JSON but missing the required `u`/`ts` fields.
        let archiveRoot = try fixture.writeHistoryLibArchive(
            chunks: [["{\"t\":\"no url or ts\"}"]]
        )

        let importer = HistoryImporter()
        await #expect(throws: (any Error).self) {
            _ = try await importer.importFrom(
                url: archiveRoot,
                modelContext: fixture.context
            )
        }
    }

    @Test("HistoryLib import rejects a chunk path that escapes the archive root")
    func historyLibImportRejectsPathTraversal() async throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let archiveRoot = try fixture.writeHistoryLibArchive(
            chunks: [["{\"u\":\"https://a.example\",\"ts\":1710000000000000}"]],
            chunkPathOverrideForID: [1: "../escaped.jsonl"]
        )

        let importer = HistoryImporter()
        await #expect(throws: (any Error).self) {
            _ = try await importer.importFrom(
                url: archiveRoot,
                modelContext: fixture.context
            )
        }
        #expect(try fixture.recordCount() == 0)
    }

    @Test("ZIP extraction rejects entries that escape the destination directory")
    func zipExtractionRejectsPathTraversal() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let zipURL = try fixture.writeZipWithEntry(path: "../escaped.json", contents: Data("x".utf8))
        let destination = fixture.tempDirectoryURL.appendingPathComponent("extract-\(UUID().uuidString)", isDirectory: true)

        #expect(throws: (any Error).self) {
            try ImportZipArchive.extractZip(at: zipURL, to: destination)
        }
    }

    @Test("ZIP entry path normalization accepts legitimate paths and rejects escapes")
    func zipEntryPathNormalization() {
        // Legitimate relative paths are preserved (independent of any symlinked
        // temp directory, which is what broke import on iOS).
        #expect(ImportZipArchive.safeRelativePath("manifest.json") == "manifest.json")
        #expect(ImportZipArchive.safeRelativePath("chunks/00000001.jsonl") == "chunks/00000001.jsonl")
        #expect(ImportZipArchive.safeRelativePath("./manifest.json") == "manifest.json")
        #expect(ImportZipArchive.safeRelativePath("archive/./chunks/x.jsonl") == "archive/chunks/x.jsonl")
        #expect(ImportZipArchive.safeRelativePath("a/../b.json") == "b.json")
        #expect(ImportZipArchive.safeRelativePath("chunks\\00000001.jsonl") == "chunks/00000001.jsonl")
        #expect(ImportZipArchive.safeRelativePath("") == "")
        #expect(ImportZipArchive.safeRelativePath("./") == "")

        // Escapes and absolute paths are rejected.
        #expect(ImportZipArchive.safeRelativePath("../escaped.json") == nil)
        #expect(ImportZipArchive.safeRelativePath("a/../../escaped.json") == nil)
        #expect(ImportZipArchive.safeRelativePath("/etc/passwd") == nil)
    }

    @Test("Directory count cache snapshot round-trips through JSON")
    func directoryCountSnapshotRoundTrips() throws {
        let snapshot = DirectoryCountSnapshot(
            schemaVersion: DirectoryCountCache.schemaVersion,
            timeZoneIdentifier: "America/New_York",
            totalCount: 7,
            days: [
                DayCountEntry(day: 1_710_000_000, count: 3),
                DayCountEntry(day: 1_709_913_600, count: 4)
            ]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DirectoryCountSnapshot.self, from: data)

        #expect(decoded.schemaVersion == DirectoryCountCache.schemaVersion)
        #expect(decoded.timeZoneIdentifier == "America/New_York")
        #expect(decoded.totalCount == 7)
        #expect(decoded.days.count == 2)
        #expect(decoded.days.reduce(0) { $0 + $1.count } == decoded.totalCount)

        let byDay = Dictionary(uniqueKeysWithValues: decoded.days.map { ($0.day, $0.count) })
        #expect(byDay[1_710_000_000] == 3)
        #expect(byDay[1_709_913_600] == 4)
    }

    @Test("Collapsing a large hierarchy prunes only its descendant expansion state")
    func hierarchyCollapsePrunesDescendants() {
        let january = Date(timeIntervalSince1970: 1_735_689_600)
        let february = Date(timeIntervalSince1970: 1_738_368_000)
        let unrelatedMonth = Date(timeIntervalSince1970: 1_767_225_600)
        let januaryDay = january
        let februaryDay = february
        let unrelatedDay = unrelatedMonth
        let yearGroup = HistoryYearGroup(
            year: 2025,
            title: "2025",
            monthGroups: [
                HistoryMonthGroup(
                    monthStart: january,
                    title: "January 2025",
                    dayGroups: [HistoryDayGroup(dayStart: januaryDay, title: "January 1")]
                ),
                HistoryMonthGroup(
                    monthStart: february,
                    title: "February 2025",
                    dayGroups: [HistoryDayGroup(dayStart: februaryDay, title: "February 1")]
                )
            ]
        )

        var years: Set<Int> = [2025, 2026]
        var months: Set<Date> = [january, february, unrelatedMonth]
        var days: Set<Date> = [januaryDay, februaryDay, unrelatedDay]
        let releasedDays = HistoryHierarchyExpansion.collapse(
            yearGroup,
            years: &years,
            months: &months,
            days: &days
        )

        #expect(years == [2026])
        #expect(months == [unrelatedMonth])
        #expect(days == [unrelatedDay])
        #expect(Set(releasedDays) == [januaryDay, februaryDay])
    }

    @Test("Clear Cache storage usage separates clearable cache from non-clearable data")
    func clearCacheStorageUsageSeparatesCategories() throws {
        let fixture = try TestFixture()
        defer { fixture.cleanup() }

        let root = fixture.tempDirectoryURL.appendingPathComponent("storage-usage", isDirectory: true)
        let dataContainer = root.appendingPathComponent("data-container", isDirectory: true)
        let libraryDirectory = dataContainer.appendingPathComponent("Library", isDirectory: true)
        let cachesDirectory = libraryDirectory.appendingPathComponent("Caches", isDirectory: true)
        let faviconDirectory = cachesDirectory.appendingPathComponent("favicons", isDirectory: true)
        let temporaryDirectory = dataContainer.appendingPathComponent("tmp", isDirectory: true)
        let applicationSupport = libraryDirectory.appendingPathComponent("Application Support", isDirectory: true)
        let cloudKitDirectory = libraryDirectory.appendingPathComponent("cloudkit", isDirectory: true)
        let cloudKitAssets = applicationSupport.appendingPathComponent("default_ckAssets", isDirectory: true)
        for directory in [faviconDirectory, temporaryDirectory, applicationSupport, cloudKitDirectory, cloudKitAssets] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let favicon = faviconDirectory.appendingPathComponent("example.bin")
        let directoryCountCache = applicationSupport.appendingPathComponent("directory-count-cache.json")
        let temporaryFile = temporaryDirectory.appendingPathComponent("stale-import.bin")
        let store = applicationSupport.appendingPathComponent("default.store")
        let wal = applicationSupport.appendingPathComponent("default.store-wal")
        let shm = applicationSupport.appendingPathComponent("default.store-shm")
        let cloudAsset = cloudKitAssets.appendingPathComponent("asset.bin")
        let cloudMetadata = cloudKitDirectory.appendingPathComponent("metadata.bin")
        let unrelated = applicationSupport.appendingPathComponent("unrelated.bin")
        let files = [favicon, directoryCountCache, temporaryFile, store, wal, shm, cloudAsset, cloudMetadata, unrelated]
        for (index, file) in files.enumerated() {
            try Data(repeating: UInt8(index), count: 1_024 + index).write(to: file)
        }

        let usage = ClearCacheStorageUsageCalculator.measure(
            cachesDirectory: cachesDirectory,
            temporaryDirectory: temporaryDirectory,
            directoryCountCacheURL: directoryCountCache,
            dataContainerDirectory: dataContainer
        )
        let allocatedSize: (URL) -> Int64 = { url in
            let keys: Set<URLResourceKey> = [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]
            let values = try? url.resourceValues(forKeys: keys)
            return Int64(
                values?.totalFileAllocatedSize
                    ?? values?.fileAllocatedSize
                    ?? values?.fileSize
                    ?? 0
            )
        }

        #expect(
            usage.clearableCacheBytes
                == allocatedSize(favicon) + allocatedSize(temporaryFile) + allocatedSize(directoryCountCache)
        )
        #expect(
            usage.nonClearableDataBytes
                == [store, wal, shm, cloudAsset, cloudMetadata, unrelated]
                    .reduce(0) { $0 + allocatedSize($1) }
        )

        ClearCacheStorageUsageCalculator.clearDirectoryContents(at: cachesDirectory)
        ClearCacheStorageUsageCalculator.clearDirectoryContents(at: temporaryDirectory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cachesDirectory.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path).isEmpty)
    }
}

private struct TestFixture {
    struct SafariRecord {
        let url: String
        let timeUsec: Int64
        let title: String
        var visitCount: Int = 1
    }

    let container: ModelContainer
    let context: ModelContext
    let tempDirectoryURL: URL

    init() throws {
        let schema = Schema([Item.self, SummarySnapshot.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)

        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryLibTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    func recordCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Item>())
    }

    func firstItem() throws -> Item? {
        try context.fetch(FetchDescriptor<Item>()).first
    }

    func insertItem(
        url: String,
        title: String,
        visitedAt: Date,
        browser: String,
        uniqueKey: String,
        visitCount: Int = 1
    ) throws {
        let item = Item(
            uniqueKey: uniqueKey,
            url: url,
            title: title,
            visitedAt: visitedAt,
            visitCount: visitCount,
            sourceBrowser: browser,
            sourceFileName: "fixture.json",
            rawTimeUsec: Int64((visitedAt.timeIntervalSince1970 * 1_000_000).rounded()),
            importedAt: visitedAt
        )
        context.insert(item)
        try context.save()
    }

    func writeSafariExportJSON(records: [SafariRecord]) throws -> URL {
        let payload: [String: Any] = [
            "metadata": [
                "browser_name": "Safari",
                "browser_version": "17.0",
                "data_type": "history",
                "export_time_usec": Int64((Date().timeIntervalSince1970 * 1_000_000).rounded()),
                "schema_version": 1
            ],
            "history": records.map { record in
                [
                    "url": record.url,
                    "time_usec": record.timeUsec,
                    "visit_count": record.visitCount,
                    "title": record.title
                ]
            }
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let outputURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    /// Builds a HistoryLib archive directory (manifest + chunks + chunk index)
    /// on disk and returns its root. Overrides let tests inject corruption.
    func writeHistoryLibArchive(
        chunks: [[String]],
        corruptShaForChunkID: Int? = nil,
        manifestRecordCountOverride: Int? = nil,
        chunkPathOverrideForID: [Int: String] = [:]
    ) throws -> URL {
        let fm = FileManager.default
        let archiveRoot = tempDirectoryURL.appendingPathComponent("archive-\(UUID().uuidString)", isDirectory: true)
        let chunksDir = archiveRoot.appendingPathComponent("chunks", isDirectory: true)
        let indexesDir = archiveRoot.appendingPathComponent("indexes", isDirectory: true)
        try fm.createDirectory(at: chunksDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: indexesDir, withIntermediateDirectories: true)

        var indexEntries: [[String: Any]] = []
        var totalRecords = 0

        for (offset, lines) in chunks.enumerated() {
            let id = offset + 1
            let fileName = String(format: "%08d.jsonl", id)
            let physicalURL = chunksDir.appendingPathComponent(fileName)
            let body = lines.map { $0 + "\n" }.joined()
            let data = Data(body.utf8)
            try data.write(to: physicalURL, options: .atomic)

            let sha: String
            if corruptShaForChunkID == id {
                sha = String(repeating: "0", count: 64)
            } else {
                sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }

            let indexPath = chunkPathOverrideForID[id] ?? "chunks/\(fileName)"
            totalRecords += lines.count
            indexEntries.append([
                "id": id,
                "path": indexPath,
                "record_count": lines.count,
                "min_ts": 0,
                "max_ts": 0,
                "sha256": sha
            ])
        }

        let chunksIndexData = try JSONSerialization.data(withJSONObject: indexEntries, options: [])
        try chunksIndexData.write(to: indexesDir.appendingPathComponent("chunks.json"), options: .atomic)

        let manifest: [String: Any] = [
            "format": "historylib",
            "format_version": 1,
            "record_count": manifestRecordCountOverride ?? totalRecords,
            "chunk_count": chunks.count,
            "indexes": ["chunks": "indexes/chunks.json"]
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [])
        try manifestData.write(to: archiveRoot.appendingPathComponent("manifest.json"), options: .atomic)

        return archiveRoot
    }

    /// Creates a ZIP archive containing a single entry at the given (possibly
    /// unsafe) path. Used to exercise path-traversal rejection.
    func writeZipWithEntry(path: String, contents: Data) throws -> URL {
        let zipURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).zip")
        let archive = try Archive(url: zipURL, accessMode: .create, pathEncoding: nil)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(contents.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, contents.count)
            return contents.subdata(in: start..<end)
        }
        return zipURL
    }
}
