import Foundation
import ZIPFoundation

enum MinimalZipArchive {
    static func createZip(fromDirectory directoryURL: URL, to zipURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }

        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .create, pathEncoding: nil)
        } catch {
            throw NSError(
                domain: "HistoryExporter",
                code: 31,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP archive at destination URL."]
            )
        }

        for entryPath in try collectFilePaths(fromDirectory: directoryURL) {
            try archive.addEntry(
                with: entryPath,
                relativeTo: directoryURL,
                compressionMethod: .deflate
            )
        }
    }

    private static func collectFilePaths(fromDirectory directoryURL: URL) throws -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var paths: [String] = []

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }

            let relativePath = fileURL.path
                .replacingOccurrences(of: directoryURL.path + "/", with: "")
                .replacingOccurrences(of: "\\", with: "/")
            paths.append(relativePath)
        }

        paths.sort()
        return paths
    }
}
