import Foundation

enum LocalStoreReset {
    /// Call only before opening the persistent container. Removing local SQLite
    /// files does not create CloudKit deletion transactions or touch other devices.
    nonisolated static func removeStore(at url: URL, fileManager: FileManager = .default) throws {
        let files = [url,
                     URL(fileURLWithPath: url.path + "-wal"),
                     URL(fileURLWithPath: url.path + "-shm"),
                     url.deletingLastPathComponent().appendingPathComponent("_" + url.lastPathComponent + "_SUPPORT")]
        for file in files where fileManager.fileExists(atPath: file.path) {
            try fileManager.removeItem(at: file)
        }
    }
}
