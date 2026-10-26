import CloudKit
import Foundation

/// Counts only history record identities, never downloading fields or assets.
/// Tokens and identities live only for one visible Manage session.
@MainActor
final class CloudHistoryCounter {
    private let database: CKDatabase
    private var tokens: [CKRecordZone.ID: CKServerChangeToken] = [:]
    private var records: [CKRecordZone.ID: Set<CKRecord.ID>] = [:]

    init(database: CKDatabase) { self.database = database }

    func count() async throws -> Int {
        try Task.checkCancellation()
        let allZones = try await database.allRecordZones()
        let zones = allZones.filter {
            $0.zoneID.zoneName == "com.apple.coredata.cloudkit.zone"
        }
        try Task.checkCancellation()
        guard allZones.isEmpty || !zones.isEmpty else { throw CountError.unrecognizedStore }
        let current = Set(zones.map(\.zoneID))
        tokens = tokens.filter { current.contains($0.key) }
        records = records.filter { current.contains($0.key) }
        for zone in zones {
            do {
                try await update(zone.zoneID)
            } catch let error as CKError where error.code == .changeTokenExpired {
                tokens[zone.zoneID] = nil
                records[zone.zoneID] = nil
                try await update(zone.zoneID)
            }
        }
        try Task.checkCancellation()
        return records.values.reduce(0) { $0 + $1.count }
    }

    private enum CountError: Error { case unrecognizedStore }

    private func update(_ zone: CKRecordZone.ID) async throws {
        var more = true
        while more {
            try Task.checkCancellation()
            let page = try await database.recordZoneChanges(
                inZoneWith: zone, since: tokens[zone], desiredKeys: [], resultsLimit: 500
            )
            try Task.checkCancellation()
            // Validate every per-record result before advancing the token.
            let changes = try page.modificationResultsByID.map { try $0.value.get().record }
            for record in changes where record.recordType == "CD_Item" {
                records[zone, default: []].insert(record.recordID)
            }
            for deletion in page.deletions { records[zone]?.remove(deletion.recordID) }
            tokens[zone] = page.changeToken
            more = page.moreComing
            await Task.yield()
        }
    }
}
