import Foundation
import GRDB

/// Backup jobs, their state and the per-file ledger (FS-22.03). The ledger is
/// the only thing that decides whether a file still needs copying.
struct BackupStore: Sendable {
    let database: AppDatabase

    // MARK: Jobs

    /// Every job in list order.
    func jobs() throws -> [BackupJob] {
        try database.reader.read { db in
            try BackupJob.order(Column("sortOrder"), Column("createdAt")).fetchAll(db)
        }
    }

    func job(id: String) throws -> BackupJob? {
        try database.reader.read { db in try BackupJob.fetchOne(db, key: id) }
    }

    /// The job already backing up this source to this place, if any — one
    /// source, connection and folder has one job (FS-22.01 §2).
    func existingJob(sourceId: String, connectionId: String, folder: String) throws -> BackupJob? {
        try database.reader.read { db in
            try BackupJob
                .filter(Column("sourceId") == sourceId && Column("connectionId") == connectionId && Column("folder") == folder)
                .fetchOne(db)
        }
    }

    /// Adds a job at the end of the list with a fresh state row.
    func add(_ job: BackupJob) throws {
        try database.writer.write { db in
            var row = job
            row.sortOrder = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM backup_jobs") ?? -1) + 1
            try row.insert(db)
            try BackupJobState(jobId: row.id).insert(db)
        }
    }

    /// Saves the form's changes. Files already copied stay where they are and
    /// stay in the ledger (FS-22.01 §2).
    func update(_ job: BackupJob) throws {
        try database.writer.write { db in try job.update(db) }
    }

    /// Removes the job with its state and ledger. Nothing at the destination
    /// is touched; the FS-15 upload history stays.
    func delete(id: String) throws {
        _ = try database.writer.write { db in try BackupJob.deleteOne(db, key: id) }
    }

    // MARK: State

    func state(jobId: String) throws -> BackupJobState {
        try database.reader.read { db in
            try BackupJobState.fetchOne(db, key: jobId) ?? BackupJobState(jobId: jobId)
        }
    }

    func save(_ state: BackupJobState) throws {
        try database.writer.write { db in try state.save(db) }
    }

    // MARK: Ledger

    /// Files of this job that need no more work — uploaded or found. One query
    /// for the whole job; the caller subtracts it from the source listing
    /// (FS-22.02 §1).
    func handledKeys(jobId: String) throws -> Set<BackupFileKey> {
        try database.reader.read { db in
            let rows = try Row.fetchCursor(db, sql: """
                SELECT itemKey, resourceKey, sourceStamp FROM backup_ledger
                WHERE jobId = ? AND outcome IN ('uploaded', 'found')
                """, arguments: [jobId])
            var keys = Set<BackupFileKey>()
            while let row = try rows.next() {
                keys.insert(BackupFileKey(itemKey: row[0], resourceKey: row[1], sourceStamp: row[2]))
            }
            return keys
        }
    }

    /// Of `keys`, the ones the ledger does not count as done, in the order given.
    func pending(_ keys: [BackupFileKey], jobId: String) throws -> [BackupFileKey] {
        let handled = try handledKeys(jobId: jobId)
        return keys.filter { !handled.contains($0) }
    }

    /// Files that failed, with how many times each was tried.
    func failedEntries(jobId: String) throws -> [BackupLedgerEntry] {
        try database.reader.read { db in
            try BackupLedgerEntry
                .filter(Column("jobId") == jobId && Column("outcome") == BackupLedgerEntry.Outcome.failed.rawValue)
                .order(Column("recordedAt"))
                .fetchAll(db)
        }
    }

    func handledCount(jobId: String) throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM backup_ledger WHERE jobId = ? AND outcome IN ('uploaded', 'found')
                """, arguments: [jobId]) ?? 0
        }
    }

    /// Records one file. An `uploaded` file also gets its FS-15 upload-history
    /// row in the same transaction, so Photo Info and Free Up Space see it
    /// (FS-22.03 §1). A later outcome for the same key replaces the earlier
    /// one; a failure counts its attempts up.
    func record(_ entry: BackupLedgerEntry, upload: ServerUploadRecord? = nil) throws {
        try database.writer.write { db in
            var row = entry
            if let previous = try BackupLedgerEntry
                .filter(Column("jobId") == entry.jobId
                    && Column("itemKey") == entry.itemKey
                    && Column("resourceKey") == entry.resourceKey
                    && Column("sourceStamp") == entry.sourceStamp)
                .fetchOne(db) {
                row.id = previous.id
                if entry.outcome == .failed { row.attempts = previous.attempts + 1 }
                try row.update(db)
            } else {
                try row.insert(db)
            }
            if let upload, entry.outcome == .uploaded {
                try ServerUploadStore.insert(upload, in: db)
            }
        }
    }
}
