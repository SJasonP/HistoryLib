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
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to create ZIP archive at destination URL.")]
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
        let rootComponents = directoryURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .pathComponents
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var paths: [String] = []

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                continue
            }

            let fileComponents = fileURL
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .pathComponents
            guard fileComponents.count > rootComponents.count,
                  fileComponents.prefix(rootComponents.count).elementsEqual(rootComponents) else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let relativePath = fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
            paths.append(relativePath)
        }

        paths.sort()
        return paths
    }
}
