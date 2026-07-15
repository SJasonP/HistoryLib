import Foundation

// On-device cache for the Library directory's per-day record counts.
//
// The Library tab groups records by year → month → day, and each group shows a
// count. Every count derives from the per-day counts (year/month totals are just
// sums), so a single day → count map is the whole cache. Persisting it lets the
// app skip the full-store scan on launch and show every count immediately.
//
// This cache is deliberately NOT part of the SwiftData/CloudKit schema, so it
// never syncs to iCloud: it is derived, device-local data (day boundaries depend
// on the device's time zone) and is cheap to rebuild. It lives as a plain JSON
// file in Application Support and is excluded from device backups.

struct DayCountEntry: Codable {
    /// Start-of-day for the device's current calendar, as epoch seconds.
    let day: Int64
    let count: Int
}

struct DirectoryCountSnapshot: Codable {
    var schemaVersion: Int
    /// The time zone the day boundaries were computed in. Day grouping shifts
    /// when the zone changes, so a mismatch invalidates the cache.
    var timeZoneIdentifier: String
    /// Sum of all day counts, i.e. the total record count the cache represents.
    /// Compared against the live store count on load to detect drift (e.g. from
    /// records arriving via iCloud sync on another device).
    var totalCount: Int
    var days: [DayCountEntry]
}

enum DirectoryCountCache {
    static let schemaVersion = 1
    private static let fileName = "directory-count-cache.json"

    private static func fileURL() -> URL? {
        let fileManager = FileManager.default
        guard let directory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func load() -> DirectoryCountSnapshot? {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(DirectoryCountSnapshot.self, from: data)
    }

    static func save(_ snapshot: DirectoryCountSnapshot) {
        guard let url = fileURL() else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            excludeFromBackup(url)
        } catch {
            #if DEBUG
            print("DirectoryCountCache save failed: \(error)")
            #endif
        }
    }

    static func clear() {
        guard let url = fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func excludeFromBackup(_ url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }
}
