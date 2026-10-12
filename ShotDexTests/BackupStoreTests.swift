import Foundation
import GRDB
import Testing
@testable import ShotDex

/// The backup ledger (FS-22.03): user data in its own tables, so it survives
/// a cleared index, and the "what is left to copy" question is one query.
@Suite @MainActor struct BackupStoreTests {
    private struct Fixture {
        let database: AppDatabase
        let store: BackupStore
        let servers: FileServerStore
        let nas: FileServer
        let job: BackupJob
    }

    private func makeFixture() throws -> Fixture {
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(name: "NAS Home", transferProtocol: .webdav, host: "127.0.0.1", username: "me", share: "")
        try servers.save(nas, password: "secret")
        let store = BackupStore(database: database)
        let job = BackupJob(sourceId: PhotoLibrarySource.id, connectionId: nas.id, folder: "Backup/iPhone")
        try store.add(job)
        return Fixture(database: database, store: store, servers: servers, nas: nas, job: job)
    }

    private func uploaded(_ n: Int, job: String) -> BackupLedgerEntry {
        BackupLedgerEntry(
            jobId: job, itemKey: "A\(n)", resourceKey: "photo:IMG_\(n).HEIC", sourceStamp: "100:1",
            remotePath: "Backup/iPhone/IMG_\(n).HEIC", byteCount: 100, sha256: "ab", outcome: .uploaded
        )
    }

    /// AC-20: Clear Local Metadata Index leaves every ledger row, and the next
    /// comparison finds nothing to copy.
    @Test func ledgerSurvivesIndexClear() throws {
        let f = try makeFixture()
        try f.database.writer.write { db in
            for n in 0..<4_118 {
                var row = uploaded(n, job: f.job.id)
                try row.insert(db)
            }
        }
        try MetadataStore(database: f.database).deleteAll()

        #expect(try f.store.handledCount(jobId: f.job.id) == 4_118)
        let source = (0..<4_118).map { BackupFileKey(itemKey: "A\($0)", resourceKey: "photo:IMG_\($0).HEIC", sourceStamp: "100:1") }
        #expect(try f.store.pending(source, jobId: f.job.id).isEmpty)
        #expect(try f.store.job(id: f.job.id) != nil)
    }

    /// AC-21: 55,000 handled files and 3 new ones — the comparison returns
    /// exactly the 3, within 3 s.
    @Test func diffAt55kIsOneQuery() throws {
        let f = try makeFixture()
        try f.database.writer.write { db in
            for n in 0..<55_000 {
                var row = uploaded(n, job: f.job.id)
                try row.insert(db)
            }
        }
        var source = (0..<55_000).map { BackupFileKey(itemKey: "A\($0)", resourceKey: "photo:IMG_\($0).HEIC", sourceStamp: "100:1") }
        let fresh = (0..<3).map { BackupFileKey(itemKey: "N\($0)", resourceKey: "photo:NEW_\($0).HEIC", sourceStamp: "200:2") }
        source.insert(contentsOf: fresh, at: 1_000)

        let start = Date()
        let pending = try f.store.pending(source, jobId: f.job.id)
        let elapsed = Date().timeIntervalSince(start)

        #expect(pending == fresh)
        #expect(elapsed < 3)
    }

    /// A file found at the destination counts as done; a failure does not,
    /// and each failure counts its attempts up.
    @Test func foundIsDoneFailedIsRetriedWithAttempts() throws {
        let f = try makeFixture()
        let key = BackupFileKey(itemKey: "A1", resourceKey: "photo:IMG_1.CR3", sourceStamp: "5:1")
        let failed = BackupLedgerEntry(jobId: f.job.id, itemKey: key.itemKey, resourceKey: key.resourceKey, sourceStamp: key.sourceStamp, outcome: .failed, lastError: "iCloud")
        try f.store.record(failed)
        try f.store.record(failed)
        #expect(try f.store.failedEntries(jobId: f.job.id).first?.attempts == 2)
        #expect(try f.store.pending([key], jobId: f.job.id) == [key])

        try f.store.record(BackupLedgerEntry(jobId: f.job.id, itemKey: key.itemKey, resourceKey: key.resourceKey, sourceStamp: key.sourceStamp, remotePath: "x/IMG_1.CR3", byteCount: 5, outcome: .found))
        #expect(try f.store.failedEntries(jobId: f.job.id).isEmpty)
        #expect(try f.store.pending([key], jobId: f.job.id).isEmpty)
    }

    /// An uploaded file writes its FS-15 history row in the same transaction;
    /// deleting the job takes the ledger but keeps that history.
    @Test func uploadWritesHistoryAndDeleteKeepsIt() throws {
        let f = try makeFixture()
        let entry = uploaded(1, job: f.job.id)
        let history = ServerUploadRecord(
            assetId: "A1", fileKey: entry.resourceKey, serverId: f.nas.id, serverName: f.nas.name,
            remotePath: entry.remotePath!, byteCount: 100, sha256: "ab"
        )
        try f.store.record(entry, upload: history)
        #expect(try ServerUploadStore(database: f.database).uploadedAssetIds() == ["A1"])

        try f.store.delete(id: f.job.id)
        #expect(try f.store.handledCount(jobId: f.job.id) == 0)
        #expect(try ServerUploadStore(database: f.database).uploadedAssetIds() == ["A1"])
    }

    /// One source, connection and folder has one job (AC-26's store half).
    @Test func sameSourceAndDestinationIsOneJob() throws {
        let f = try makeFixture()
        #expect(try f.store.existingJob(sourceId: PhotoLibrarySource.id, connectionId: f.nas.id, folder: "Backup/iPhone")?.id == f.job.id)
        #expect(throws: (any Error).self) {
            try f.store.add(BackupJob(sourceId: PhotoLibrarySource.id, connectionId: f.nas.id, folder: "Backup/iPhone"))
        }
    }

    /// Deleting the connection deletes its jobs (FS-22.03 §1).
    @Test func deletingConnectionDeletesJobs() throws {
        let f = try makeFixture()
        try f.servers.delete(id: f.nas.id)
        #expect(try f.store.jobs().isEmpty)
    }

    /// Settings this build cannot read fall back field by field.
    @Test func unreadableSettingFallsBackAlone() throws {
        let json = #"{"content":"somethingNew","onlyOnWiFi":false,"organize":{"levels":"yearMonth","monthStyle":"martian"}}"#
        let settings = try JSONDecoder().decode(BackupSettings.self, from: Data(json.utf8))
        #expect(settings.content == .photosAndVideos)
        #expect(settings.onlyOnWiFi == false)
        #expect(settings.organize.levels == .yearMonth)
        #expect(settings.organize.monthStyle == .abbreviated)
    }
}
