import Foundation
import SQLite3

enum DatabaseJournalMaintenance {
    enum Outcome: Int, Sendable { case completed, busy, unavailable }
    /// Ask SQLite to checkpoint and truncate completed WAL pages under its locks.
    /// Never unlink a journal, alter tables/indexes, VACUUM, or create a database.
    nonisolated static func reclaim(databaseURLs: [URL]) async -> Outcome {
        await Task.detached(priority: .utility) {
            var outcome = Outcome.completed
            for url in databaseURLs {
                let next = checkpoint(at: url)
                if next.rawValue > outcome.rawValue { outcome = next }
            }
            return outcome
        }.value
    }

    nonisolated static func checkpoint(at url: URL) -> Outcome {
        guard url.isFileURL else { return .unavailable }
        guard FileManager.default.fileExists(atPath: url.path) else { return .completed }
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
        defer { if let database { sqlite3_close(database) } }
        guard opened == SQLITE_OK, let database else { return .unavailable }
        // Zero timeout: a live reader/writer must never be interrupted or waited on.
        sqlite3_busy_timeout(database, 0)
        // Opening a connection is lazy. Read its schema before asking for a checkpoint.
        guard sqlite3_exec(database, "PRAGMA schema_version", nil, nil, nil) == SQLITE_OK else { return .unavailable }
        switch sqlite3_wal_checkpoint_v2(database, "main", SQLITE_CHECKPOINT_TRUNCATE, nil, nil) {
        case SQLITE_OK: return .completed
        case SQLITE_BUSY, SQLITE_LOCKED: return .busy
        default: return .unavailable
        }
    }
}
