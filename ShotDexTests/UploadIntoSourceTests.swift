import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.03 §8 — uploading into a server source's Folder.
@Suite struct UploadIntoSourceTests {
    private static func record(_ id: String) -> PhotoMetadata {
        PhotoMetadata(assetId: id, creationDate: 1_790_000_000, modificationDate: 1_790_000_000, mediaType: MediaKind.photo.storedValue,
                      cameraManufacturer: nil, cameraModel: nil, normalizedCameraModel: nil, normalizedCameraManufacturer: nil,
                      lensManufacturer: nil, lensModel: nil, normalizedLensModel: nil, originalFilename: nil, iso: nil, aperture: nil,
                      shutterSpeedSeconds: nil, shutterSpeedDisplay: nil, focalLength: nil, focalLengthIn35mm: nil,
                      calculatedEquivalentFocalLength: nil, equivalentFocalLength: nil, sensorFormat: nil, cropFactor: nil,
                      width: 4032, height: 3024, fileSize: 2_000_000, latitude: nil, longitude: nil, isFavorite: false,
                      indexedAt: 1_790_000_000, exifStatus: ExifStatus.indexed.rawValue)
    }

    /// AC-56: 20 Photos photos are uploaded to NAS Home/Photos/2026, the
    /// Folder of the NAS Home source. Each becomes a second copy of its
    /// photo at once — the library still counts 20, each photo has 2
    /// copies. Free Up Space's confirmation adds "They stay in ShotDex from
    /// NAS Home.", and after the 20 leave Photos they are still in the grid.
    /// An upload outside the Folder, or to a server that is not a source,
    /// adds no copy.
    @Test func uploadedFileIsACopy() throws {
        let database = try AppDatabase.makeEmpty()
        let metadata = MetadataStore(database: database)
        let ids = (1...20).map { "ASSET-\($0)/L0/001" }
        for id in ids { try metadata.upsert(Self.record(id)) }
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        try servers.save(FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u",
                                    folder: "Photos/2026"), password: "pw")
        try servers.save(FileServer(id: "C2", name: "Office", transferProtocol: .sftp, host: "office", username: "u", folder: "In"), password: "pw")
        _ = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        let uploads = ServerUploadStore(database: database)

        for (n, id) in ids.enumerated() {
            try uploads.record(ServerUploadRecord(assetId: id, fileKey: "photo", serverId: "C1", serverName: "NAS Home",
                                                  remotePath: "Photos/2026/IMG_\(n).HEIC", byteCount: 2_000_000, sha256: "h\(n)"))
        }
        try uploads.record(ServerUploadRecord(assetId: ids[0], fileKey: "photo", serverId: "C1", serverName: "NAS Home",
                                              remotePath: "Elsewhere/IMG_0.HEIC", byteCount: 2_000_000, sha256: "h0"))
        try uploads.record(ServerUploadRecord(assetId: ids[0], fileKey: "photo", serverId: "C2", serverName: "Office",
                                              remotePath: "In/IMG_0.HEIC", byteCount: 2_000_000, sha256: "h0"))

        let library = LibraryQueries(database: database)
        #expect(try library.count(matching: FilterCriteria()) == 20)
        let copies = try database.reader.read { db in
            try Int.fetchAll(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE missingSince IS NULL GROUP BY photoId")
        }
        #expect(copies == Array(repeating: 2, count: 20))

        let names = try uploads.keepingSources(assetIds: ids)
        #expect(names == ["NAS Home"])
        #expect(FreeUpSpaceNote.line(keepingSources: names) == "They stay in ShotDex from NAS Home.")
        #expect(FreeUpSpaceNote.message("They move to Recently Deleted.", keepingSources: names)
                == "They move to Recently Deleted.\n\nThey stay in ShotDex from NAS Home.")

        try metadata.deleteAssets(ids: ids)
        try PhotoOrphanStore(database: database).markGoneFromLibrary(ids: ids)
        #expect(try library.count(matching: FilterCriteria()) == 20)
        #expect(try database.reader.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photos WHERE orphanedAt IS NOT NULL") } == 0)

        // A photo only in Photos still leaves with its asset, and the note
        // is not offered when even one would go.
        try metadata.upsert(Self.record("SOLO/L0/001"))
        #expect(try uploads.keepingSources(assetIds: ["SOLO/L0/001"]).isEmpty)
        try metadata.deleteAssets(ids: ["SOLO/L0/001"])
        #expect(try library.count(matching: FilterCriteria()) == 20)
    }

    /// A RAW + JPEG asset uploads as two files: one copy, the RAW its
    /// original and the JPEG its pair, as a listing pairs them.
    @Test func pairUploadsAsOneCopy() throws {
        let database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).upsert(Self.record("PAIR/L0/001"))
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        try servers.save(FileServer(id: "C1", name: "NAS Home", transferProtocol: .smb, host: "nas.local", username: "u", folder: ""), password: "pw")
        _ = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
        let uploads = ServerUploadStore(database: database)
        for (key, path) in [("photo", "2026/DSC1.JPG"), ("alternatePhoto", "2026/DSC1.ARW")] {
            try uploads.record(ServerUploadRecord(assetId: "PAIR/L0/001", fileKey: key, serverId: "C1", serverName: "NAS Home",
                                                  remotePath: path, byteCount: 1_000, sha256: key))
        }
        let row = try #require(try database.reader.read { db in
            try Row.fetchOne(db, sql: "SELECT relativePath, pairedPath FROM photo_copies WHERE kind = 'server'")
        })
        #expect(row["relativePath"] as String == "2026/DSC1.ARW")
        #expect(row["pairedPath"] as String? == "2026/DSC1.JPG")
        #expect(UploadIntoSource.relativePath(of: "Photos/2026/A.JPG", in: "/Photos/2026/") == "A.JPG")
        #expect(UploadIntoSource.relativePath(of: "Photos/20260/A.JPG", in: "Photos/2026") == nil)
    }
}
