import Foundation
import ZIPFoundation

enum ImportZipArchive {
    private nonisolated static let maxEntryCount = 100_000
    private nonisolated static let maxEntryBytes: UInt64 = 4 * 1024 * 1024 * 1024
    private nonisolated static let minimumFreeSpaceReserve: Int64 = 512 * 1024 * 1024

    static func extractInBackground(at zipURL: URL, to destination: URL) async throws {
        let task = Task.detached { try extractZip(at: zipURL, to: destination) }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    nonisolated static func extractZip(at zipURL: URL, to destinationDirectoryURL: URL) throws {
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read, pathEncoding: nil)
        } catch {
            throw NSError(
                domain: "HistoryImport",
                code: 61,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to open ZIP archive for import.")]
            )
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)
        let availableCapacity = try? destinationDirectoryURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage
        let extractionBudget = availableCapacity.map { UInt64(max(0, $0 - minimumFreeSpaceReserve)) }

        var entryCount = 0
        var extractedBytes: UInt64 = 0
        for entry in archive {
            try Task.checkCancellation()
            entryCount += 1
            guard entryCount <= maxEntryCount else {
                throw NSError(domain: "HistoryImport", code: 64, userInfo: [NSLocalizedDescriptionKey: String(localized: "ZIP archive contains too many entries.")])
            }
            let entryBytes = UInt64(entry.uncompressedSize)
            guard entryBytes <= maxEntryBytes,
                  extractionBudget.map({ extractedBytes <= $0 && entryBytes <= $0 - extractedBytes }) ?? true else {
                throw NSError(domain: "HistoryImport", code: 65, userInfo: [NSLocalizedDescriptionKey: String(localized: "ZIP archive is too large to import safely.")])
            }
            if entry.type == .symlink {
                throw NSError(
                    domain: "HistoryImport",
                    code: 63,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "ZIP archive contains unsupported symbolic link entries.")]
                )
            }

            // Validate the entry's relative path instead of comparing absolute
            // filesystem paths. Absolute-path comparison is unreliable here: the
            // destination root exists (so on iOS its path canonicalizes
            // /var -> /private/var) but each entry's destination does not exist
            // yet (so it stays /var), and the mismatched prefixes reject every
            // legitimate entry. Checking the relative path for `..` escapes and
            // absolute roots is symlink- and platform-independent.
            guard let relativePath = safeRelativePath(entry.path) else {
                throw NSError(
                    domain: "HistoryImport",
                    code: 62,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "ZIP entry path is outside destination directory.")]
                )
            }
            if relativePath.isEmpty {
                // Root or empty entry ("." / "/"): nothing to extract.
                continue
            }

            let destinationURL = destinationDirectoryURL.appendingPathComponent(relativePath)

            if entry.type == .directory {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                continue
            }

            let parentURL = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
            guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let handle = try FileHandle(forWritingTo: destinationURL)
            defer { try? handle.close() }
            var actualBytes: UInt64 = 0
            let checksum = try archive.extract(entry) { data in
                try Task.checkCancellation()
                let count = UInt64(data.count)
                guard actualBytes <= entryBytes, count <= entryBytes - actualBytes,
                      actualBytes <= maxEntryBytes, count <= maxEntryBytes - actualBytes,
                      extractionBudget.map({ extractedBytes <= $0 && count <= $0 - extractedBytes }) ?? true else {
                    throw HistoryTransferError.resourceLimitExceeded
                }
                try handle.write(contentsOf: data)
                actualBytes += count
                extractedBytes += count
            }
            guard actualBytes == entryBytes, checksum == entry.checksum else { throw HistoryTransferError.invalidJSON }
        }
    }

    /// Normalizes a ZIP entry path to a safe relative path inside the destination.
    /// Returns `nil` if the path is absolute or escapes the root via `..`, or an
    /// empty string for a root/empty entry that has nothing to write.
    nonisolated static func safeRelativePath(_ rawPath: String) -> String? {
        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") {
            return nil
        }

        var components: [String] = []
        for component in normalized.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." {
                continue
            }
            if component == ".." {
                if components.isEmpty {
                    return nil
                }
                components.removeLast()
            } else {
                components.append(String(component))
            }
        }
        return components.joined(separator: "/")
    }
}
