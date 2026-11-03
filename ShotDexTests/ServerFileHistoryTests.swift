import Foundation
import Testing
@testable import ShotDex

/// FS-17.01 §4b: renames and deletes on the server reach both histories,
/// for every connection that points at the same files.
@Suite @MainActor struct ServerFileHistoryTests {
    private struct Stores {
        let servers: FileServerStore
        let uploads: ServerUploadStore
        let downloads: ServerDownloadStore
        let history: ServerFileHistory
    }

    private func makeStores() throws -> Stores {
        let database = try AppDatabase.makeEmpty()
        return Stores(
            servers: FileServerStore(database: database, passwords: InMemoryPasswordStore()),
            uploads: ServerUploadStore(database: database),
            downloads: ServerDownloadStore(database: database),
            history: ServerFileHistory(database: database)
        )
    }

    private func upload(_ assetId: String, _ path: String, on server: FileServer) -> ServerUploadRecord {
        ServerUploadRecord(assetId: assetId, fileKey: "photo:\(path)", serverId: server.id, serverName: server.name,
                           remotePath: path, byteCount: 10, sha256: "ab")
    }

    @Test func pathsMatchTheItemAndWhatIsInside() {
        #expect(ServerHistoryPaths.isAffected("2024/a.CR3", by: "2024"))
        #expect(ServerHistoryPaths.isAffected("2024", by: "2024/"))
        #expect(!ServerHistoryPaths.isAffected("2024-old/a.CR3", by: "2024"))
        #expect(!ServerHistoryPaths.isAffected("a.CR3", by: ""))
        #expect(ServerHistoryPaths.renamed("photos/A.CR3", from: "photos/A.CR3", to: "photos/Beach.CR3") == "photos/Beach.CR3")
        #expect(ServerHistoryPaths.renamed("photos/Trip/x.JPG", from: "photos/Trip", to: "photos/Holiday") == "photos/Holiday/x.JPG")
        #expect(ServerHistoryPaths.renamed("photos/Tripod.JPG", from: "photos/Trip", to: "photos/Holiday") == nil)
    }

    /// AC-26, the data half: the proof under a deleted folder goes for
    /// every connection to the same host; another host keeps its own.
    @Test func deleteDropsProofOnEveryConnectionToTheHost() throws {
        let stores = try makeStores()
        let a = FileServer(name: "A", transferProtocol: .smb, host: "nas.local", username: "me", folder: "photos")
        let b = FileServer(name: "B", transferProtocol: .smb, host: "NAS.local", username: "other", folder: "photos/2024")
        let c = FileServer(name: "C", transferProtocol: .smb, host: "office.local", username: "me", folder: "photos")
        let sftp = FileServer(name: "S", transferProtocol: .sftp, host: "nas.local", username: "me")
        for server in [a, b, c, sftp] { try stores.servers.save(server, password: "p") }
        try stores.uploads.record(upload("1", "photos/2024/a.CR3", on: a))
        try stores.uploads.record(upload("2", "photos/2024/x/b.JPG", on: b))
        try stores.uploads.record(upload("3", "photos/2024/a.CR3", on: c))
        try stores.uploads.record(upload("4", "photos/2024-old/a.CR3", on: a))
        try stores.uploads.record(upload("5", "photos/2024/a.CR3", on: sftp))

        let dropped = try stores.history.forgetUploads(at: "photos/2024", on: a)

        #expect(dropped == 2)
        #expect(try stores.uploads.uploadedAssetIds() == ["3", "4", "5"])
    }

    /// AC-25, the data half: a rename moves the upload and download paths.
    @Test func renameMovesBothHistories() throws {
        let stores = try makeStores()
        let a = FileServer(name: "A", transferProtocol: .smb, host: "nas.local", username: "me", folder: "photos")
        try stores.servers.save(a, password: "p")
        try stores.uploads.record(upload("1", "photos/A.CR3", on: a))
        try stores.downloads.record(ServerDownloadRecord(assetId: "9", serverId: a.id, serverName: "A", remotePath: "photos/A.JPG", byteCount: 5, sha256: "cd"))

        try stores.history.move("photos/A.CR3", to: "photos/Beach.CR3", on: a)
        try stores.history.move("photos/A.JPG", to: "photos/Beach.JPG", on: a)

        #expect(try stores.uploads.uploads(assetId: "1").map(\.remotePath) == ["photos/Beach.CR3"])
        let known = try stores.downloads.knownFiles(serverId: a.id, paths: ["photos/Beach.JPG", "photos/A.JPG"])
        #expect(known.map(\.remotePath) == ["photos/Beach.JPG"])
    }

    /// FS-19.08 §6: a run's moves in one write; an SFTP login with another
    /// home is other files, so its history stays where it was.
    @Test func batchMoveFollowsEveryChangeOnTheSameFilesOnly() throws {
        let stores = try makeStores()
        let me = FileServer(name: "Me", transferProtocol: .sftp, host: "nas.local", username: "me")
        let alsoMe = FileServer(name: "Me again", transferProtocol: .sftp, host: "NAS.local", username: "me")
        let you = FileServer(name: "You", transferProtocol: .sftp, host: "nas.local", username: "you")
        for server in [me, alsoMe, you] { try stores.servers.save(server, password: "p") }
        try stores.uploads.record(upload("1", "A/IMG_1.JPG", on: me))
        try stores.uploads.record(upload("2", "B/IMG_2.JPG", on: alsoMe))
        try stores.uploads.record(upload("3", "A/IMG_1.JPG", on: you))

        try stores.history.move([(from: "A/IMG_1.JPG", to: "C/IMG_1.JPG"), (from: "B/IMG_2.JPG", to: "C/IMG_2.JPG")], on: me)

        #expect(try stores.uploads.uploads(assetId: "1").map(\.remotePath) == ["C/IMG_1.JPG"])
        #expect(try stores.uploads.uploads(assetId: "2").map(\.remotePath) == ["C/IMG_2.JPG"])
        #expect(try stores.uploads.uploads(assetId: "3").map(\.remotePath) == ["A/IMG_1.JPG"])
    }

    @Test func sameFilesNeedsTheSameLoginOnSFTPAndTheSameBaseOnWebDAV() {
        let smb = FileServer(name: "a", transferProtocol: .smb, host: "nas.local", port: 445, username: "me")
        #expect(ServerIdentity.sameFiles(smb, FileServer(name: "b", transferProtocol: .smb, host: "NAS.local", port: 445, username: "you")))
        #expect(!ServerIdentity.sameFiles(smb, FileServer(name: "c", transferProtocol: .smb, host: "nas.local", port: 4450, username: "me")))
        let sftp = FileServer(name: "s", transferProtocol: .sftp, host: "nas.local", username: "me")
        #expect(!ServerIdentity.sameFiles(sftp, FileServer(name: "t", transferProtocol: .sftp, host: "nas.local", username: "you")))
        let dav = FileServer(name: "d", transferProtocol: .webdav, host: "nas.local", username: "me", share: "/dav/")
        #expect(ServerIdentity.sameFiles(dav, FileServer(name: "e", transferProtocol: .webdav, host: "nas.local", username: "x", share: "dav")))
        #expect(!ServerIdentity.sameFiles(dav, FileServer(name: "f", transferProtocol: .webdav, host: "nas.local", username: "me", share: "other")))
    }
}

/// FS-15.02 §8 — FS-15 AC-49: Uploaded to Server lists where the copies are.
@Suite struct UploadDestinationsTests {
    @Test func groupsByConnectionAndFolder() {
        let rows: [UploadDestinations.Row] = [
            .init(connectionName: "NAS", remotePath: "photos/2024/a.CR3", assetId: "A", uploadedAt: 10),
            .init(connectionName: "NAS", remotePath: "photos/2024/a.JPG", assetId: "A", uploadedAt: 11),
            .init(connectionName: "NAS", remotePath: "photos/2024/b.CR3", assetId: "B", uploadedAt: 30),
            .init(connectionName: "Mac", remotePath: "Backup/a.CR3", assetId: "A", uploadedAt: 20),
            .init(connectionName: "NAS", remotePath: "c.CR3", assetId: "C", uploadedAt: 5),
            .init(connectionName: "NAS", remotePath: "photos/2024/gone.CR3", assetId: "G", uploadedAt: 40),
        ]
        let places = UploadDestinations.group(rows, present: ["A", "B", "C"])
        #expect(places.map(\.connectionName) == ["NAS", "Mac", "NAS"])
        #expect(places.map(\.folder) == ["photos/2024", "Backup", ""])
        #expect(places[0].assetIds == ["B", "A"])
        #expect(places[1].assetIds == ["A"])
        // Nothing left in the library for a place: it goes.
        #expect(UploadDestinations.group(rows, present: ["C"]).map(\.folder) == [""])
    }

    /// FS-19.08 §6: a Move takes Backup's ledger along, for every job on a
    /// connection to the same files.
    @Test func moveTakesTheBackupLedgerAlong() throws {
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "me", folder: "photos")
        try servers.save(nas, password: "pw")
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO backup_jobs (id, sourceId, connectionId, folder, sourceFolder, settings, sortOrder, createdAt)
                VALUES ('J1', 'photos-library', ?, 'photos/Tuan', '', '{}', 0, 1)
                """, arguments: [nas.id])
            try db.execute(sql: """
                INSERT INTO backup_ledger (jobId, itemKey, resourceKey, sourceStamp, remotePath, outcome, attempts, recordedAt)
                VALUES ('J1', 'a', 'photo', 's', 'photos/Tuan/IMG_1.JPG', 'uploaded', 1, 1),
                       ('J1', 'b', 'photo', 's', 'photos/Tuan/IMG_2.JPG', 'uploaded', 1, 1)
                """)
        }

        try ServerFileHistory(database: database).move("photos/Tuan/IMG_1.JPG", to: "photos/Shared/IMG_1.JPG", on: nas)

        let paths = try database.reader.read { db in try String.fetchAll(db, sql: "SELECT remotePath FROM backup_ledger ORDER BY itemKey") }
        #expect(paths == ["photos/Shared/IMG_1.JPG", "photos/Tuan/IMG_2.JPG"])
    }
}
