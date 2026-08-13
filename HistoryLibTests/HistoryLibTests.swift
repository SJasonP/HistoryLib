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
}
