import Foundation

struct ClearCacheStorageUsage: Sendable {
    let clearableCacheBytes: Int64
    let nonClearableDataBytes: Int64
    let databaseBytes: Int64
    let databaseJournalBytes: Int64

    nonisolated init(clearableCacheBytes: Int64, nonClearableDataBytes: Int64, databaseBytes: Int64 = 0, databaseJournalBytes: Int64 = 0) {
        self.clearableCacheBytes = clearableCacheBytes
        self.nonClearableDataBytes = nonClearableDataBytes
        self.databaseBytes = databaseBytes
        self.databaseJournalBytes = databaseJournalBytes
    }
}

enum ClearCacheStorageUsageCalculator {
    nonisolated static func measure(databaseURLs: [URL] = []) async -> ClearCacheStorageUsage {
        let task = Task.detached(priority: .utility) { measureSynchronously(databaseURLs: databaseURLs) }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private nonisolated static func measureSynchronously(databaseURLs: [URL]) -> ClearCacheStorageUsage {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let temporaryDirectory = fileManager.temporaryDirectory
        let dataContainerDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let directoryCountCacheURL = applicationSupport?
            .appendingPathComponent("directory-count-cache.json")

        return measure(
            cachesDirectory: caches,
            temporaryDirectory: temporaryDirectory,
            directoryCountCacheURL: directoryCountCacheURL,
            dataContainerDirectory: dataContainerDirectory,
            fileManager: fileManager,
            databaseURLs: databaseURLs
        )
    }

    nonisolated static func measure(
        cachesDirectory: URL?,
        temporaryDirectory: URL?,
        directoryCountCacheURL: URL?,
        dataContainerDirectory: URL?,
        fileManager: FileManager = .default,
        databaseURLs: [URL] = []
    ) -> ClearCacheStorageUsage {
        var clearableCacheBytes: Int64 = 0
        if let cachesDirectory {
            clearableCacheBytes += allocatedSize(
                of: cachesDirectory,
                fileManager: fileManager
            )
        }
        if let temporaryDirectory {
            for directory in disposableTemporaryDirectories(in: temporaryDirectory) {
                clearableCacheBytes += allocatedSize(of: directory, fileManager: fileManager)
            }
        }
        if let directoryCountCacheURL {
            clearableCacheBytes += allocatedSize(
                of: directoryCountCacheURL,
                fileManager: fileManager
            )
        }

        let dataContainerBytes = dataContainerDirectory.map {
            allocatedSize(of: $0, fileManager: fileManager)
        } ?? 0
        let nonClearableDataBytes = max(0, dataContainerBytes - clearableCacheBytes)

        return ClearCacheStorageUsage(
            clearableCacheBytes: clearableCacheBytes,
            nonClearableDataBytes: nonClearableDataBytes,
            databaseBytes: databaseURLs.reduce(0) { $0 + allocatedSize(of: $1, fileManager: fileManager) },
            databaseJournalBytes: databaseURLs.reduce(0) { total, url in
                total + ["-wal", "-shm"].reduce(0) {
                    $0 + allocatedSize(of: URL(fileURLWithPath: url.path + $1), fileManager: fileManager)
                }
            }
        )
    }

    nonisolated static func clearCacheDirectories() async {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            clearDirectoryContents(at: caches, fileManager: fileManager)
            clearDisposableTemporaryDirectories(in: fileManager.temporaryDirectory, fileManager: fileManager)
        }.value
    }

    nonisolated static func disposableTemporaryDirectories(in root: URL) -> [URL] {
        // Never delete framework-owned SQLite scratch/journal files or live stores.
        ["Import", "EncryptedImport", "Export", "Staging", "ImportedExportDocument"].map {
            root.appendingPathComponent($0, isDirectory: true)
        }
    }

    nonisolated static func clearDisposableTemporaryDirectories(in root: URL, fileManager: FileManager = .default) {
        for directory in disposableTemporaryDirectories(in: root) {
            clearDirectoryContents(at: directory, fileManager: fileManager)
        }
    }

    nonisolated static func clearDirectoryContents(
        at directory: URL?,
        fileManager: FileManager = .default
    ) {
        guard let directory,
              let entries = try? fileManager.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else {
            return
        }

        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
    }

    private nonisolated static func allocatedSize(of url: URL, fileManager: FileManager) -> Int64 {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return allocatedFileSize(at: url)
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
            )
        }
        return total
    }

    private nonisolated static func allocatedFileSize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        return Int64(
            values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
        )
    }

}
