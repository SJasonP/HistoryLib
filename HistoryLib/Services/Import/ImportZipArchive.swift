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
                userInfo: [NSLocalizedDescriptionKey: "Failed to open ZIP archive for import."]
            )
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        let rootPath = destinationDirectoryURL.standardizedFileURL.path
        for entry in archive {
            if entry.type == .symlink {
                throw NSError(
                    domain: "HistoryImport",
                    code: 63,
                    userInfo: [NSLocalizedDescriptionKey: "ZIP archive contains unsupported symbolic link entries."]
                )
            }

            let destinationURL = destinationDirectoryURL.appendingPathComponent(entry.path)
            let standardizedDestination = destinationURL.standardizedFileURL
            let destinationPath = standardizedDestination.path
            let isInsideDestination = destinationPath == rootPath || destinationPath.hasPrefix(rootPath + "/")
            guard isInsideDestination else {
                throw NSError(
                    domain: "HistoryImport",
                    code: 62,
                    userInfo: [NSLocalizedDescriptionKey: "ZIP entry path is outside destination directory."]
                )
            }

            if entry.type == .directory {
                try fileManager.createDirectory(at: standardizedDestination, withIntermediateDirectories: true)
                continue
            }

            let parentURL = standardizedDestination.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: standardizedDestination)
        }
    }
}
