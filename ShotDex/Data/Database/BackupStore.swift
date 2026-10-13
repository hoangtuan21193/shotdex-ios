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

    /// Removes jobs whose FS-19 source is gone, with their state and ledger.
    func removeJobsWithoutSource() throws {
        try database.writer.write { db in
            try db.execute(sql: """
                DELETE FROM backup_jobs
                WHERE sourceId != ? AND sourceId NOT IN (SELECT id FROM sources)
                """, arguments: [PhotoLibrarySource.id])
        }
    }

    /// Saves the form's changes. Files already copied stay where they are and
    /// stay in the ledger (FS-22.01 §2).
    ///
    /// A new destination folder is a new tree: what this device knew of the
    /// old one is dropped and the next run lists the new one (FS-22.05 §3).
    func update(_ job: BackupJob) throws {
        try database.writer.write { db in
            let previous = try BackupJob.fetchOne(db, key: job.id)
            try job.update(db)
            if let previous, previous.folder != job.folder || previous.connectionId != job.connectionId {
                try db.execute(sql: "DELETE FROM backup_destination_files WHERE jobId = ?", arguments: [job.id])
                try db.execute(sql: "DELETE FROM backup_index_segments WHERE jobId = ?", arguments: [job.id])
                try db.execute(sql: "UPDATE backup_job_state SET lastTreeScanAt = NULL WHERE jobId = ?", arguments: [job.id])
            }
        }
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

    /// Files of this job that need no more work — uploaded, found or a
    /// duplicate of a file already there. One query
    /// for the whole job; the caller subtracts it from the source listing
    /// (FS-22.02 §1).
    func handledKeys(jobId: String) throws -> Set<BackupFileKey> {
        try database.reader.read { db in
            let rows = try Row.fetchCursor(db, sql: """
                SELECT itemKey, resourceKey, sourceStamp FROM backup_ledger
                WHERE jobId = ? AND outcome IN ('uploaded', 'found', 'duplicate')
                """, arguments: [jobId])
            var keys = Set<BackupFileKey>()
            while let row = try rows.next() {
                keys.insert(BackupFileKey(itemKey: row[0], resourceKey: row[1], sourceStamp: row[2]))
            }
            return keys
        }
    }

    /// How many items have at least one file done (uploaded, found, duplicate).
    func handledItemCount(jobId: String) throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT itemKey) FROM backup_ledger WHERE jobId = ? AND outcome IN ('uploaded', 'found', 'duplicate')
                """, arguments: [jobId]) ?? 0
        }
    }

    /// Files backed up, newest first — the Backed-Up Files list.
    func handledEntries(jobId: String, limit: Int = 500) throws -> [BackupLedgerEntry] {
        try database.reader.read { db in
            try BackupLedgerEntry
                .filter(Column("jobId") == jobId && [BackupLedgerEntry.Outcome.uploaded.rawValue, BackupLedgerEntry.Outcome.found.rawValue].contains(Column("outcome")))
                .order(Column("recordedAt").desc, Column("id").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Items with at least one file done (uploaded, found, duplicate).
    func handledItemKeys(jobId: String) throws -> Set<String> {
        try database.reader.read { db in
            Set(try String.fetchAll(db, sql: """
                SELECT DISTINCT itemKey FROM backup_ledger WHERE jobId = ? AND outcome IN ('uploaded', 'found', 'duplicate')
                """, arguments: [jobId]))
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
                SELECT COUNT(*) FROM backup_ledger WHERE jobId = ? AND outcome IN ('uploaded', 'found', 'duplicate')
                """, arguments: [jobId]) ?? 0
        }
    }

    /// Records one file. An `uploaded` file — and a `duplicate`, whose bytes
    /// matched by SHA-256 — also gets its FS-15 upload-history row in the same
    /// transaction, so Photo Info and Free Up Space see it (FS-22.03 §1). A later outcome for the same key replaces the earlier
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
            if entry.outcome != .failed {
                // Earlier failures of this file (under an older stamp) are over.
                try db.execute(sql: """
                    DELETE FROM backup_ledger
                    WHERE jobId = ? AND itemKey = ? AND resourceKey = ? AND outcome = 'failed' AND sourceStamp != ?
                    """, arguments: [entry.jobId, entry.itemKey, entry.resourceKey, entry.sourceStamp])
            }
            if let upload, entry.outcome == .uploaded || entry.outcome == .duplicate {
                try ServerUploadStore.insert(upload, in: db)
            }
        }
    }

    /// Files skipped because the same bytes were already at the destination,
    /// newest first — the Already on list (FS-22.05 §5).
    func duplicateEntries(jobId: String, limit: Int = 500) throws -> [BackupLedgerEntry] {
        try database.reader.read { db in
            try BackupLedgerEntry
                .filter(Column("jobId") == jobId && Column("outcome") == BackupLedgerEntry.Outcome.duplicate.rawValue)
                .order(Column("recordedAt").desc, Column("id").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func duplicateCount(jobId: String) throws -> Int {
        try database.reader.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM backup_ledger WHERE jobId = ? AND outcome = 'duplicate'
                """, arguments: [jobId]) ?? 0
        }
    }

    // MARK: Destination contents (FS-22.05)

    /// Files at the destination known to hold these bytes.
    func destinationFiles(jobId: String, sha256: String) throws -> [BackupDestinationFile] {
        // Sorted here, not in SQL: an ORDER BY path makes SQLite walk the
        // primary key over the whole job instead of the hash index.
        try database.reader.read { db in
            try BackupDestinationFile.fetchAll(db, sql: """
                SELECT * FROM backup_destination_files INDEXED BY backup_destination_files_sha WHERE jobId = ? AND sha256 = ?
                """, arguments: [jobId, sha256])
        }.sorted { $0.path < $1.path }
    }

    /// Files at the destination of exactly this size whose bytes nobody has
    /// hashed yet.
    func unhashedDestinationFiles(jobId: String, size: Int64) throws -> [BackupDestinationFile] {
        try database.reader.read { db in
            try BackupDestinationFile.fetchAll(db, sql: """
                SELECT * FROM backup_destination_files INDEXED BY backup_destination_files_size
                WHERE jobId = ? AND size = ? AND sha256 IS NULL
                """, arguments: [jobId, size])
        }.sorted { $0.path < $1.path }
    }

    func destinationFileCount(jobId: String) throws -> Int {
        try database.reader.read { db in try BackupDestinationFile.filter(Column("jobId") == jobId).fetchCount(db) }
    }

    /// Adds or replaces what is known of one destination file.
    func saveDestinationFile(_ file: BackupDestinationFile) throws {
        try database.writer.write { db in try file.save(db) }
    }

    /// The file is not there (or not as recorded) any more.
    func removeDestinationFile(jobId: String, path: String) throws {
        _ = try database.writer.write { db in
            try BackupDestinationFile.deleteOne(db, key: ["jobId": jobId, "path": path])
        }
    }

    /// Takes in a fresh listing of the destination tree (FS-22.05 §3): files
    /// no longer there are forgotten, new ones are added unhashed, and a
    /// known file keeps its SHA-256 only while its size — and its date, once
    /// known — is unchanged. Records when the tree was listed.
    ///
    /// Plain cached statements, not records: a tree is tens of thousands of
    /// rows (FS-22.05 AC-38).
    func applyListing(_ files: [BackupDestinationScan.File], jobId: String, at now: Int = Int(Date().timeIntervalSince1970)) throws {
        try database.writer.write { db in
            var known: [String: (size: Int64, modified: Int?)] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT path, size, modified FROM backup_destination_files WHERE jobId = ?", arguments: [jobId])
            while let row = try rows.next() { known[row[0]] = (row[1], row[2]) }

            let insert = try db.cachedStatement(sql: """
                INSERT INTO backup_destination_files (jobId, path, size, modified, sha256, origin, needsPublish, seenAt)
                VALUES (?, ?, ?, ?, NULL, 'listed', 0, ?)
                """)
            let keep = try db.cachedStatement(sql: """
                UPDATE backup_destination_files SET modified = COALESCE(?, modified), seenAt = ? WHERE jobId = ? AND path = ?
                """)
            let changed = try db.cachedStatement(sql: """
                UPDATE backup_destination_files SET size = ?, modified = ?, sha256 = NULL, needsPublish = 0, seenAt = ?
                WHERE jobId = ? AND path = ?
                """)
            for file in files {
                let modified = file.modified.map { Int($0.timeIntervalSince1970) }
                if let old = known.removeValue(forKey: file.path) {
                    let differs = old.size != file.size || (old.modified != nil && modified != nil && old.modified != modified)
                    if differs {
                        try changed.execute(arguments: [file.size, modified, now, jobId, file.path])
                    } else {
                        try keep.execute(arguments: [modified, now, jobId, file.path])
                    }
                } else {
                    try insert.execute(arguments: [jobId, file.path, file.size, modified, now])
                }
            }
            let forget = try db.cachedStatement(sql: "DELETE FROM backup_destination_files WHERE jobId = ? AND path = ?")
            for path in known.keys { try forget.execute(arguments: [jobId, path]) }
            try db.execute(sql: "UPDATE backup_job_state SET lastTreeScanAt = ? WHERE jobId = ?", arguments: [now, jobId])
        }
    }

    // MARK: Shared index (FS-22.05 §2)

    /// Segments of the shared index already taken in, with the size each had.
    func readSegments(jobId: String) throws -> [String: Int64] {
        try database.reader.read { db in
            var sizes: [String: Int64] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT name, size FROM backup_index_segments WHERE jobId = ?", arguments: [jobId])
            while let row = try rows.next() { sizes[row[0]] = row[1] }
            return sizes
        }
    }

    /// Takes in one segment's lines, in one transaction, and remembers the
    /// segment as read.
    func mergeIndex(_ lines: [BackupContentIndex.Line], jobId: String, segment: String, size: Int64, at now: Int = Int(Date().timeIntervalSince1970)) throws {
        try database.writer.write { db in
            let find = try db.cachedStatement(sql: """
                SELECT size, modified, sha256, origin, needsPublish, seenAt FROM backup_destination_files WHERE jobId = ? AND path = ?
                """)
            let save = try db.cachedStatement(sql: """
                INSERT OR REPLACE INTO backup_destination_files (jobId, path, size, modified, sha256, origin, needsPublish, seenAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for line in lines {
                let existing = try Row.fetchOne(find, arguments: [jobId, line.path]).map { row in
                    BackupDestinationFile(
                        jobId: jobId, path: line.path, size: row[0], modified: row[1], sha256: row[2],
                        origin: BackupDestinationFile.Origin(rawValue: row[3]) ?? .listed, needsPublish: row[4], seenAt: row[5]
                    )
                }
                guard let file = BackupContentIndex.merged(line, into: existing, jobId: jobId, now: now) else { continue }
                try save.execute(arguments: [
                    jobId, file.path, file.size, file.modified, file.sha256, file.origin.rawValue, file.needsPublish, file.seenAt,
                ])
            }
            try db.execute(sql: """
                INSERT OR REPLACE INTO backup_index_segments (jobId, name, size, readAt) VALUES (?, ?, ?, ?)
                """, arguments: [jobId, segment, size, now])
        }
    }

    /// Hashes this device knows that the shared index does not yet.
    func unpublishedDestinationFiles(jobId: String) throws -> [BackupDestinationFile] {
        try database.reader.read { db in
            try BackupDestinationFile
                .filter(Column("jobId") == jobId && Column("needsPublish") == true && Column("sha256") != nil)
                .order(Column("path"))
                .fetchAll(db)
        }
    }

    func hasUnpublishedDestinationFiles(jobId: String) throws -> Bool {
        try database.reader.read { db in
            try BackupDestinationFile
                .filter(Column("jobId") == jobId && Column("needsPublish") == true && Column("sha256") != nil)
                .fetchCount(db) > 0
        }
    }

    /// These rows are in the segment just written; that segment is this
    /// device's own and is not read back.
    func markPublished(_ files: [BackupDestinationFile], jobId: String, segment: String, size: Int64, at now: Int = Int(Date().timeIntervalSince1970)) throws {
        try database.writer.write { db in
            for file in files {
                try db.execute(sql: """
                    UPDATE backup_destination_files SET needsPublish = 0 WHERE jobId = ? AND path = ? AND sha256 = ?
                    """, arguments: [jobId, file.path, file.sha256])
            }
            try db.execute(sql: """
                INSERT OR REPLACE INTO backup_index_segments (jobId, name, size, readAt) VALUES (?, ?, ?, ?)
                """, arguments: [jobId, segment, size, now])
        }
    }
}
