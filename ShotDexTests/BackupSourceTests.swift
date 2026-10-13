import Foundation
import GRDB
import Testing
@testable import ShotDex

/// The two real sources' failure lines and the FS-19 folder source end to end.
@Suite @MainActor struct BackupSourceTests {
    /// AC-22 (denied half): no Photos access stops the run with its own
    /// status, nothing written. The `.limited` half is checked on the
    /// simulator (FS-22.04 §2).
    @Test func limitedAccessCopiesVisibleOnly() async throws {
        let f = try BackupFixture(photos: 3)
        f.source.listError = BackupSourceError.noPhotosAccess
        let denied = await f.runner().run()
        #expect(denied.stop == .blocked(.noPhotosAccess))
        #expect(f.client.uploadCount == 0)

        // What the source lists is all that is copied: 120 visible of a
        // larger library.
        f.source.listError = nil
        let visible = (0..<120).map { BackupFixture.item(1_000 + $0, name: "V_\($0).HEIC", bytes: 64).0 }
        var contents: [String: Data] = [:]
        for n in 0..<120 { contents[FakeAssetExporter.key("A\(1_000 + n)", "1:V_\(n).HEIC")] = BackupFixture.payload(1_000 + n, bytes: 64) }
        f.source.replace(visible)
        let run = await f.runner(exporter: FakeAssetExporter(contents: contents)).run()
        #expect(run.stop == .finished)
        #expect(f.remoteFiles.count == 120)
    }

    /// AC-23: a folder source of 20 RAW files whose drive is away stops as
    /// Source Offline; back again, the next run copies all 20, and a drive
    /// pulled mid-run stops there and resumes after.
    @Test func folderSourceOfflineThenResume() async throws {
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(id: "S1", name: "NAS Office", transferProtocol: .smb, host: "127.0.0.1", username: "me", share: "photo")
        try servers.save(nas, password: "pw")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("T7-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sourceId = try SourceStore(database: database).addFolder(
            name: "T7 RAW Archive", bookmark: try folder.bookmarkData(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive"
        )
        try await database.writer.write { db in
            for n in 0..<20 {
                let name = "DSC0\(4500 + n).ARW"
                try BackupFixture.payload(n, bytes: 256).write(to: folder.appendingPathComponent(name))
                try db.execute(sql: """
                    INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, size, modifiedAt)
                    VALUES (?, ?, ?, 'file', ?, ?, 256, 100)
                    """, arguments: ["C\(n)", "P\(n)", sourceId, name, name.lowercased()])
            }
        }
        let store = BackupStore(database: database)
        var settings = BackupSettings()
        settings.organize.levels = .noFolders
        let job = BackupJob(sourceId: sourceId, connectionId: nas.id, folder: "Archive/T7", settings: settings)
        try store.add(job)
        let client = InMemoryRemoteFileClient()
        let roots = FolderSourceRoots(database: database)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("bk-\(UUID().uuidString)")
        func runner(_ exporter: any AssetFileExporting) -> BackupRunner {
            BackupRunner(
                job: job, destination: BackupDestination(connectionId: nas.id, connectionName: nas.name),
                client: client, store: store, source: SourceCopyBackupSource(database: database, roots: roots),
                exporter: exporter, workDirectory: work, deviceId: "PHONE-A"
            )
        }
        let exporter = SourceCopyBackupExporter(database: database, roots: roots, servers: servers, sourceId: sourceId)

        // Unplugged: the folder is not there. (Moving it would not do — a
        // bookmark follows a moved folder.)
        let saved = folder.deletingLastPathComponent().appendingPathComponent("saved-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: folder, to: saved)
        let unplug: @Sendable () -> Void = { try? FileManager.default.removeItem(at: folder) }
        let plugIn: () throws -> Void = {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.copyItem(at: saved, to: folder)
        }
        unplug()
        #expect(await runner(exporter).run().stop == .blocked(.sourceOffline))
        #expect(client.uploadCount == 0)

        // Plugged back in, then pulled after 7 files.
        try plugIn()
        let pulling = PullingExporter(base: exporter, after: 7, pull: unplug)
        #expect(await runner(pulling).run().stop == .blocked(.sourceOffline))
        #expect(try store.handledCount(jobId: job.id) == 7)

        try plugIn()
        let resumed = await runner(exporter).run()
        #expect(resumed.stop == .finished)
        #expect(resumed.progress.total == 13)
        #expect(client.files.keys.filter { $0.hasPrefix("Archive/T7/DSC0") && $0.hasSuffix(".ARW") }.count == 20)
    }
}

/// Serves `after` files, then runs `pull` and reports the drive gone.
final class PullingExporter: AssetFileExporting, @unchecked Sendable {
    private let lock = NSLock()
    private let base: any AssetFileExporting
    private let after: Int
    private let pull: @Sendable () -> Void
    private var served = 0

    init(base: any AssetFileExporting, after: Int, pull: @escaping @Sendable () -> Void) {
        self.base = base
        self.after = after
        self.pull = pull
    }

    func export(assetId: String, file: AssetUploadFile, into directory: URL) async throws -> URL {
        let pulled = lock.withLock { () -> Bool in
            served += 1
            return served > after
        }
        if pulled {
            pull()
            throw BackupSourceError.offline
        }
        return try await base.export(assetId: assetId, file: file, into: directory)
    }
}
