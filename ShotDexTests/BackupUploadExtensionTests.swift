import Foundation
import Photos
import Testing
@testable import ShotDex

/// The Photos background-upload path for WebDAV backups (FS-22.02 §3c).
@Suite @MainActor struct BackupUploadExtensionTests {
    /// AC-27 (the app's half): part files the extension sent are read back,
    /// checked and renamed on the next run — nothing is sent again. The
    /// extension being woken by Photos is not reachable on the simulator.
    @Test func partFilesVerifiedOnNextRun() async throws {
        let f = try BackupFixture(photos: 2)
        for (key, data) in f.contents {
            let name = String(key.split(separator: ":").last!)
            f.client.put("Backup/iPhone/\(name).shotdex-part", data)
        }
        let uploads = f.client.uploadCount

        let result = await f.runner().run()

        #expect(result.stop == .finished)
        #expect(f.client.uploadCount == uploads)
        #expect(f.partFiles.isEmpty)
        #expect(f.remoteFiles.count == 2)
        #expect(try f.store.handledCount(jobId: f.job.id) == 2)
        #expect(try ServerUploadStore(database: f.database).uploadedAssetIds().count == 2)
    }

    /// A part that does not match is replaced by a fresh upload.
    @Test func wrongPartIsSentAgain() async throws {
        let f = try BackupFixture(photos: 1)
        f.client.put("Backup/iPhone/IMG_0.HEIC.shotdex-part", Data(repeating: 9, count: 4_000))
        let uploads = f.client.uploadCount
        _ = await f.runner().run()
        #expect(f.client.uploadCount == uploads + 1)
        #expect(f.remoteFiles["Backup/iPhone/IMG_0.HEIC"] == f.contents.values.first)
    }

    /// AC-28: only Photos → WebDAV jobs are handed over, and the extension
    /// is on only with one of them and full access.
    @Test func disabledWithoutWebDAVJobOrFullAccess() {
        let dav = FileServer(id: "D", name: "DAV", transferProtocol: .webdav, host: "nas.local", port: 5006, username: "me", usesTLS: true)
        let smb = FileServer(id: "S", name: "SMB", transferProtocol: .smb, host: "nas.local", username: "me")
        let photosToDav = BackupJob(id: "J1", sourceId: PhotoLibrarySource.id, connectionId: "D", folder: "Backup/iPhone")
        let photosToSmb = BackupJob(id: "J2", sourceId: PhotoLibrarySource.id, connectionId: "S", folder: "Backup/iPhone")
        let folderToDav = BackupJob(id: "J3", sourceId: "folder-1", connectionId: "D", folder: "Archive")

        let none = BackupUploadExtensionSync.config(jobs: [photosToSmb, folderToDav], servers: [dav, smb])
        #expect(none.jobs.isEmpty)
        #expect(!BackupUploadExtensionSync.shouldEnable(none, status: .authorized))

        let one = BackupUploadExtensionSync.config(jobs: [photosToDav, photosToSmb], servers: [dav, smb])
        #expect(one.jobs.map(\.jobId) == ["J1"])
        #expect(one.jobs.first?.baseURL == "https://nas.local:5006")
        #expect(BackupUploadExtensionSync.shouldEnable(one, status: .authorized))
        #expect(!BackupUploadExtensionSync.shouldEnable(one, status: .limited))
    }

    /// The PUT goes to the part name under the job's folder, folders first.
    @Test func requestsTargetThePartName() throws {
        var settings = BackupSettings()
        settings.onlyOnWiFi = true
        let job = BackupUploadConfig.Job(jobId: "J", baseURL: "http://127.0.0.1:8090", folder: "Backup/iPhone", settings: settings, account: "D")
        let put = try #require(BackupUploadRequests.put(relativePath: "2025/Oct/2025.10.12/IMG 1.HEIC", job: job, authorization: "Basic x"))
        #expect(put.httpMethod == "PUT")
        #expect(put.url?.absoluteString == "http://127.0.0.1:8090/Backup/iPhone/2025/Oct/2025.10.12/IMG%201.HEIC.shotdex-part")
        #expect(put.value(forHTTPHeaderField: "Authorization") == "Basic x")
        #expect(!put.allowsExpensiveNetworkAccess)
        #expect(BackupUploadRequests.folders(for: "2025/Oct/2025.10.12/IMG 1.HEIC", job: job)
            == ["Backup", "Backup/iPhone", "Backup/iPhone/2025", "Backup/iPhone/2025/Oct", "Backup/iPhone/2025/Oct/2025.10.12"])
    }
}
