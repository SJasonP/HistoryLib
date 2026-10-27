import CloudKit
import Foundation
import Observation

@MainActor
@Observable
final class ManageDiagnostics {
    var localCount: Int?
    var cloudCount: Int?
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
        accountMessage = String(localized: "Checking…")
        cloudMessage = String(localized: "Checking…")
        while !Task.isCancelled {
            do {
                let status = try await container.accountStatus()
                try Task.checkCancellation()
                accountMessage = Self.accountMessage(for: status)
                if status == .available {
                    let count = try await counter.count()
                    try Task.checkCancellation()
                    cloudCount = count
                    cloudMessage = String(localized: "Cloud count is a server snapshot, not sync progress.")
                } else {
                    cloudCount = nil
                    cloudMessage = String(localized: "Cloud records are unavailable.")
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                cloudCount = nil
                cloudMessage = String(localized: "Cloud records are unavailable.")
            }
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
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
