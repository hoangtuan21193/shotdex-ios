import Foundation
import Testing
@testable import ShotDex

/// AC-7: "In Library" from the upload and download histories.
@Suite struct ServerImportIndexTests {
    @Test func inLibraryFromHistory() throws {
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(name: "NAS", transferProtocol: .smb, host: "nas.local", username: "u", share: "photos")
        let other = FileServer(name: "Other", transferProtocol: .smb, host: "other.local", username: "u", share: "photos")
        try servers.save(nas, password: nil)
        try servers.save(other, password: nil)
        let uploads = ServerUploadStore(database: database)
        let downloads = ServerDownloadStore(database: database)
        try uploads.record(ServerUploadRecord(assetId: "A", fileKey: "photo:A.CR3", serverId: nas.id, serverName: "NAS",
                                              remotePath: "Trip/A.CR3", byteCount: 300, sha256: "aa"))
        try downloads.record(ServerDownloadRecord(assetId: "B", serverId: nas.id, serverName: "NAS",
                                                  remotePath: "Trip/B.JPG", byteCount: 50, sha256: "bb"))
        try downloads.record(ServerDownloadRecord(assetId: "C", serverId: nas.id, serverName: "NAS",
                                                  remotePath: "Trip/C.JPG", byteCount: 70, sha256: "cc"))
        // Same path on another server does not count.
        try downloads.record(ServerDownloadRecord(assetId: "D", serverId: other.id, serverName: "Other",
                                                  remotePath: "Trip/D.JPG", byteCount: 10, sha256: "dd"))

        func entry(_ name: String, _ size: Int64) -> RemoteEntry { RemoteEntry(name: name, isDirectory: false, size: size, modified: nil) }
        let photos = [
            ServerPhoto(files: [entry("A.JPG", 60), entry("A.CR3", 300)]),   // RAW uploaded from this device
            ServerPhoto(files: [entry("B.JPG", 50)]),                        // downloaded earlier
            ServerPhoto(files: [entry("C.JPG", 71)]),                        // changed on the server since
            ServerPhoto(files: [entry("D.JPG", 10)]),                        // other server's history
            ServerPhoto(files: [entry("E.JPG", 5)]),
        ]
        let known = try downloads.knownFiles(serverId: nas.id, paths: photos.flatMap { $0.files.map { "Trip/\($0.name)" } })
        #expect(ServerImportIndex.inLibrary(photos: photos, folder: "Trip", known: known, existingAssetIds: ["A", "B", "C", "D"]) == ["A.JPG", "B.JPG"])
        // Deleted from the library: no longer "In Library".
        #expect(ServerImportIndex.inLibrary(photos: photos, folder: "Trip", known: known, existingAssetIds: ["B"]) == ["B.JPG"])
        #expect(ServerImportIndex.knownChecksum(path: "Trip/A.CR3", size: 300, known: known) == "aa")
        #expect(ServerImportIndex.knownChecksum(path: "Trip/C.JPG", size: 71, known: known) == nil)

        // Deleting the server keeps the download rows, name and all.
        try servers.delete(id: nas.id)
        #expect(try downloads.count() == 3)
    }
}
