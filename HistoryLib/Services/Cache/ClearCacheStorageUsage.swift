import Foundation

struct ClearCacheStorageUsage: Sendable {
    let clearableCacheBytes: Int64
    let nonClearableDataBytes: Int64

    nonisolated init(clearableCacheBytes: Int64, nonClearableDataBytes: Int64) {
        self.clearableCacheBytes = clearableCacheBytes
        self.nonClearableDataBytes = nonClearableDataBytes
    }
}

enum ClearCacheStorageUsageCalculator {
    nonisolated static func measure() async -> ClearCacheStorageUsage {
        await Task.detached(priority: .utility) {
            measureSynchronously()
        }.value
    }

    private nonisolated static func measureSynchronously() -> ClearCacheStorageUsage {
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
            fileManager: fileManager
        )
    }

    nonisolated static func measure(
        cachesDirectory: URL?,
        temporaryDirectory: URL?,
        directoryCountCacheURL: URL?,
        dataContainerDirectory: URL?,
        fileManager: FileManager = .default
    ) -> ClearCacheStorageUsage {
        var clearableCacheBytes: Int64 = 0
        if let cachesDirectory {
            clearableCacheBytes += allocatedSize(
                of: cachesDirectory,
                fileManager: fileManager
            )
        }
        if let temporaryDirectory {
            clearableCacheBytes += allocatedSize(
                of: temporaryDirectory,
                fileManager: fileManager
            )
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
            nonClearableDataBytes: nonClearableDataBytes
        )
    }

    nonisolated static func clearCacheDirectories() async {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            clearDirectoryContents(at: caches, fileManager: fileManager)
            clearDirectoryContents(at: fileManager.temporaryDirectory, fileManager: fileManager)
        }.value
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
