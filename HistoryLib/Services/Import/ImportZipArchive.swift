import Foundation
import ZIPFoundation

enum ImportZipArchive {
    static func extractZip(at zipURL: URL, to destinationDirectoryURL: URL) throws {
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

        for entry in archive {
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
            _ = try archive.extract(entry, to: destinationURL)
        }
    }

    /// Normalizes a ZIP entry path to a safe relative path inside the destination.
    /// Returns `nil` if the path is absolute or escapes the root via `..`, or an
    /// empty string for a root/empty entry that has nothing to write.
    static func safeRelativePath(_ rawPath: String) -> String? {
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
