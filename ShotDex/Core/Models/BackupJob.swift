import Foundation
import GRDB

/// One backup: a source watched and copied to a folder on a file server
/// (FS-22.01). User-made, so it lives in its own table, never in
/// `photo_metadata` (BD-02 §1).
struct BackupJob: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// `PhotoLibrarySource.id` for the Photos library, else an FS-19 source id.
    var sourceId: String
    /// The FS-15 connection the files go to.
    var connectionId: String
    /// Folder on the connection, relative to its root, `/`-separated.
    var folder: String
    /// For an FS-19 source, the folder inside it that is backed up, relative
    /// to the source; empty = the whole source. Unused for Photos.
    var sourceFolder: String = ""
    var settings: BackupSettings
    /// Position in the job list; the order jobs run in (FS-22.02 §2).
    var sortOrder: Int
    var createdAt: Int

    init(
        id: String = UUID().uuidString,
        sourceId: String,
        connectionId: String,
        folder: String,
        sourceFolder: String = "",
        settings: BackupSettings = BackupSettings(),
        sortOrder: Int = 0,
        createdAt: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.sourceId = sourceId
        self.connectionId = connectionId
        self.folder = folder
        self.sourceFolder = sourceFolder
        self.settings = settings
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

extension BackupJob: FetchableRecord, PersistableRecord {
    static let databaseTableName = "backup_jobs"

    /// Settings this build cannot read at all fall back to the defaults, so
    /// one damaged row never takes the whole job list with it.
    init(row: Row) {
        id = row["id"]
        sourceId = row["sourceId"]
        connectionId = row["connectionId"]
        folder = row["folder"]
        sourceFolder = row["sourceFolder"] ?? ""
        let json: Data? = (row["settings"] as String?).map { Data($0.utf8) } ?? row["settings"]
        settings = json.flatMap { try? JSONDecoder().decode(BackupSettings.self, from: $0) } ?? BackupSettings()
        sortOrder = row["sortOrder"]
        createdAt = row["createdAt"]
    }
}

/// Where a job stands between runs (FS-22.03 §1). One row per job.
struct BackupJobState: Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case watching, uploading, waitingForWiFi, waitingToCharge, unreachable,
             sourceOffline, pausedByUser, pausedBySystem, destinationFull,
             waitingForStorage, noPhotosAccess, signInFailed
    }

    var jobId: String
    /// Archived Photos change token; nil = compare the whole source.
    var changeToken: Data?
    var lastCheckedAt: Int?
    var status: Status = .watching
    /// Numbers for the status line, e.g. "812 of 2,940" on a system pause.
    var statusDone: Int?
    var statusTotal: Int?
    /// True once a run finished with the ledger empty at its start — later
    /// runs read "N New" instead of "Backing Up" (FS-22.02 §5).
    var hasFinishedFirstRun = false
    /// When the destination tree was last listed (FS-22.05 §3); nil = never.
    var lastTreeScanAt: Int?

    init(jobId: String) {
        self.jobId = jobId
    }
}

extension BackupJobState: FetchableRecord, PersistableRecord {
    static let databaseTableName = "backup_job_state"
}

/// One file of one source item a job has dealt with (FS-22.03 §1). The ledger
/// alone decides "already backed up".
struct BackupLedgerEntry: Codable, Hashable, Sendable {
    enum Outcome: String, Codable, Sendable {
        /// Written by this job and checked by reading it back.
        case uploaded
        /// Already at the destination with the same name and size.
        case found
        /// Not copied; retried on later runs.
        case failed
        /// The same bytes are already somewhere in the destination folder —
        /// `remotePath` is that file (FS-22.05 §4).
        case duplicate
    }

    var id: Int64?
    var jobId: String
    /// Photos asset id, or FS-19 copy id.
    var itemKey: String
    /// Which file of the item — `AssetUploadFile.key`.
    var resourceKey: String
    /// Size and modification time at the source, so a changed file is a new
    /// entry rather than a match.
    var sourceStamp: String
    var remotePath: String?
    var byteCount: Int64?
    var sha256: String?
    var outcome: Outcome
    var attempts: Int
    var lastError: String?
    var recordedAt: Int
    /// The file's name on this device.
    var localName: String?

    init(
        id: Int64? = nil,
        jobId: String,
        itemKey: String,
        resourceKey: String,
        sourceStamp: String,
        remotePath: String? = nil,
        byteCount: Int64? = nil,
        sha256: String? = nil,
        outcome: Outcome,
        attempts: Int = 1,
        lastError: String? = nil,
        recordedAt: Int = Int(Date().timeIntervalSince1970),
        localName: String? = nil
    ) {
        self.id = id
        self.jobId = jobId
        self.itemKey = itemKey
        self.resourceKey = resourceKey
        self.sourceStamp = sourceStamp
        self.remotePath = remotePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.outcome = outcome
        self.attempts = attempts
        self.lastError = lastError
        self.recordedAt = recordedAt
        self.localName = localName
    }

    /// What a source file is matched on: the item, which of its files, and
    /// the stamp it had.
    var key: BackupFileKey {
        BackupFileKey(itemKey: itemKey, resourceKey: resourceKey, sourceStamp: sourceStamp)
    }
}

extension BackupLedgerEntry: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "backup_ledger"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// The identity a source file is looked up by in the ledger.
struct BackupFileKey: Hashable, Sendable {
    var itemKey: String
    var resourceKey: String
    var sourceStamp: String
}

/// One file in a job's destination folder, as far as this device knows
/// (FS-22.05 §2): listed there, read from the shared index, or written here.
struct BackupDestinationFile: Codable, Hashable, Sendable {
    enum Origin: String, Codable, Sendable {
        /// Seen by listing the destination tree.
        case listed
        /// Read from another device's (or an earlier install's) index segment.
        case index
        /// Written by this device.
        case own
    }

    var jobId: String
    /// Relative to the job's folder.
    var path: String
    var size: Int64
    /// Modification time at the destination, seconds; nil = not known.
    var modified: Int?
    var sha256: String?
    var origin: Origin
    var needsPublish = false
    var seenAt = Int(Date().timeIntervalSince1970)
}

extension BackupDestinationFile: FetchableRecord, PersistableRecord {
    static let databaseTableName = "backup_destination_files"
}
