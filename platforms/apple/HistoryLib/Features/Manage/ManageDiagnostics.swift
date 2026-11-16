import CloudKit
import Foundation
import Observation

@MainActor
@Observable
final class ManageDiagnostics {
    private enum CloudCheckError: Error {
        case timedOut
    }

    enum CloudRecordsState: Equatable {
        case checking
        case unavailable
        case available(Int)
    }

    var localCount: Int?
    var cloudCount: Int?
    var cloudRecordsState: CloudRecordsState = .checking
    var storageUsage: ClearCacheStorageUsage?
    var accountMessage = String(localized: "Checking…")
    var cloudMessage = String(localized: "Checking…")
    var isClearing = false

    func monitorLocal(
        count: () throws -> Int,
        measure: () async -> ClearCacheStorageUsage
    ) async {
        while !Task.isCancelled {
            localCount = try? count()
            let measured = await measure()
            guard !Task.isCancelled else { return }
            storageUsage = measured
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }

    func monitorCloud() async {
        let container = CKContainer(identifier: "iCloud.com.SJasonP.HistoryLib")
        let counter = CloudHistoryCounter(database: container.privateCloudDatabase)
        cloudCount = nil
        cloudRecordsState = .checking
        accountMessage = String(localized: "Checking…")
        cloudMessage = String(localized: "Checking…")
        while !Task.isCancelled {
            do {
                let status = try await withTimeout(.seconds(10)) {
                    try await container.accountStatus()
                }
                try Task.checkCancellation()
                accountMessage = Self.accountMessage(for: status)
                if status == .available {
                    let count = try await withTimeout(.seconds(20)) {
                        try await counter.count()
                    }
                    try Task.checkCancellation()
                    cloudCount = count
                    cloudRecordsState = .available(count)
                    cloudMessage = String(localized: "Cloud count is a server snapshot, not sync progress.")
                } else {
                    cloudCount = nil
                    cloudRecordsState = .unavailable
                    cloudMessage = String(localized: "Cloud records are unavailable.")
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                cloudCount = nil
                cloudRecordsState = .unavailable
                cloudMessage = String(localized: "Cloud records are unavailable.")
            }
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
        }
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw CloudCheckError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    static func accountMessage(for status: CKAccountStatus) -> String {
        switch status {
        case .available: String(localized: "Available")
        case .noAccount: String(localized: "Not Signed In")
        case .restricted: String(localized: "Restricted")
        case .couldNotDetermine, .temporarilyUnavailable: String(localized: "Unavailable")
        @unknown default: String(localized: "Unavailable")
        }
    }
}
