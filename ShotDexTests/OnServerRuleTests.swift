import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.07 §3, §7: `Source is <server>` counts Photos items whose every
/// original file has a byte-identical file on the server — read from the
/// per-file hashes, with no merge of photos.
@MainActor
struct OnServerRuleTests {
    /// AC-75: 65 Photos items have every file on the NAS — 40 under
    /// `Shared/`, 25 under `Tuấn/`; 35 have none. Nothing is merged, and the
    /// NAS's own photos (rows of their own in the library) are not counted:
    /// the album is the list of Photos items safe to delete.
    @Test func wholeSourceWithoutMerge() async throws {
        let f = try OnServerFixture(photos: 100)
        for n in 0..<65 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
            try f.server(n < 40 ? "Shared/2025/IMG_\(n).HEIC" : "Tuấn/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: "sha\(n)")
        }
        for n in 65..<100 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
        }
        #expect(try await f.count(.isExactly) == 65)
        #expect(try await f.count(.isNot) == 35)
        #expect(try await f.database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_aliases")
        } == 0)
    }

    /// AC-74: of 100 checked items, 40 have their files under `Shared/` and
    /// 25 only under `Tuấn/` — the folder narrows to the 40, at any depth,
    /// and a folder whose name only starts the same does not count.
    @Test func folderScope() async throws {
        let f = try OnServerFixture(photos: 100)
        for n in 0..<100 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
        }
        for n in 0..<40 { try f.server("Shared/2025/\(n % 3)/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: "sha\(n)") }
        for n in 40..<65 { try f.server("Tuấn/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: "sha\(n)") }
        try f.server("Shared copy/IMG_99.HEIC", size: 1_099, sha: "sha99")
        #expect(try await f.count(.isExactly, folder: "Shared") == 40)
        #expect(try await f.count(.isExactly, folder: "/shared/") == 40)
        #expect(try await f.count(.isNot, folder: "Shared") == 60)
        #expect(try await f.count(.isExactly, folder: "Tuấn") == 25)
        #expect(try await f.count(.isExactly, folder: "Shared/2025/1") == 13)
    }

    /// AC-80: 30 of 100 items are checked; 70 have a same-size file on the
    /// NAS still to hash — on either side. Those 70 are in neither list.
    @Test func uncheckedInNeither() async throws {
        let f = try OnServerFixture(photos: 100)
        for n in 0..<30 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
        }
        try f.server("Shared/IMG_0.HEIC", size: 1_000, sha: "sha0")
        for n in 30..<65 {
            // Photos side not hashed yet; the NAS file is.
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), nil)])
            try f.server("Shared/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: "sha\(n)")
        }
        for n in 65..<100 {
            // Photos side hashed; the NAS file of its size is not.
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
            try f.server("Shared/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: nil)
        }
        #expect(try await f.count(.isExactly, folder: "Shared") == 1)
        #expect(try await f.count(.isNot, folder: "Shared") == 29)
        // Never listed: in neither either.
        let g = try OnServerFixture(photos: 3)
        #expect(try await g.count(.isExactly) + g.count(.isNot) == 0)
    }

    /// AC-74: the chip reads the source by name, with its folder.
    @Test func chipNamesSourceAndFolder() throws {
        let rule = SmartAlbumRule(field: .source, op: .isExactly, text: "S1", folder: "Shared")
        #expect(rule.displaySummary(naming: ["S1": "NAS Home"]) == "Source is NAS Home › Shared")
        #expect(SmartAlbumRule(field: .source, op: .isExactly, text: "S1").displaySummary(naming: ["S1": "NAS Home"])
                == "Source is NAS Home")
        #expect(rule.compactDisplaySummary(naming: ["S1": "NAS Home"]) == "source NAS Home › Shared")
        // A saved album without the folder field still decodes.
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","field":"source","op":"isExactly","text":"S1","boolValue":true,"focalMode":"actual"}"#
        #expect(try JSONDecoder().decode(SmartAlbumRule.self, from: Data(old.utf8)).folder == nil)
    }

    /// The folder browser answers from the server's root; the condition
    /// keeps the folder from the source's root.
    @Test func folderPathFromSourceRoot() {
        #expect(SourceFolderPath.relative(chosen: "/iCloud Photo/Shared/2025", root: "iCloud Photo") == "Shared/2025")
        #expect(SourceFolderPath.relative(chosen: "iCloud Photo", root: "/iCloud Photo/") == "")
        #expect(SourceFolderPath.relative(chosen: "iCloud Photos/Shared", root: "iCloud Photo") == nil)
        #expect(SourceFolderPath.relative(chosen: "Shared", root: "") == "Shared")
        #expect(SourceFolderPath.absolute("Shared", root: "iCloud Photo") == "iCloud Photo/Shared")
        #expect(SourceFolderPath.absolute(nil, root: "iCloud Photo") == "iCloud Photo")
    }

    /// AC-77: a Live Photo whose video is not on the NAS is not there — it
    /// is in **is not**.
    @Test func livePhotoNeedsVideo() async throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:IMG_1.HEIC", .photo, 2_000, "heic"), ("9:IMG_1.MOV", .pairedVideo, 3_000, "mov")])
        try f.server("Shared/IMG_1.HEIC", size: 2_000, sha: "heic")
        #expect(try await f.count(.isExactly) == 0)
        #expect(try await f.count(.isNot) == 1)

        try f.server("Shared/IMG_1.MOV", size: 3_000, sha: "mov")
        #expect(try await f.count(.isExactly) == 1)
        #expect(try await f.count(.isNot) == 0)
    }

    /// AC-78: RAW+JPEG with both files on the NAS — the JPEG as the paired
    /// companion of the RAW copy — is there.
    @Test func rawPairBothFiles() async throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:DSC_1.JPG", .photo, 4_000, "jpg"), ("4:DSC_1.ARW", .raw, 24_000, "arw")])
        try f.server("Shared/DSC_1.ARW", size: 24_000, sha: "arw", companion: ("Shared/DSC_1.JPG", 4_000, "jpg"))
        #expect(try await f.count(.isExactly) == 1)
    }

    /// AC-79: a re-compressed JPEG and a copy with XMP written into it are
    /// not the photo — different bytes, different size, never hashed.
    @Test func notByteIdenticalIsNotPresent() async throws {
        let f = try OnServerFixture(photos: 2)
        try f.photo(0, files: [("1:IMG_1.HEIC", .photo, 5_000, nil)])
        try f.photo(1, files: [("1:IMG_2.HEIC", .photo, 6_000, nil)])
        try f.server("Shared/IMG_1.JPG", size: 1_800, sha: nil)
        try f.server("Shared/IMG_2.HEIC", size: 6_412, sha: nil)
        #expect(try await f.count(.isExactly) == 0)
        // No file of their size: known not there, no download needed.
        #expect(try await f.count(.isNot) == 2)
    }

    /// AC-99: an item edited in Photos needs its render on the NAS; the
    /// original alone is not enough.
    @Test func editedNeedsRender() async throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:IMG_1.HEIC", .photo, 7_000, "orig"), ("5:FullSizeRender.HEIC", .editedPhoto, 7_500, "edit")])
        try f.server("Shared/IMG_1.HEIC", size: 7_000, sha: "orig")
        #expect(try await f.count(.isExactly) == 0)
        #expect(try await f.count(.isNot) == 1)

        try f.server("Shared/IMG_1_edited.HEIC", size: 7_500, sha: "edit")
        #expect(try await f.count(.isExactly) == 1)
    }

    /// An edit made after the files were listed may have added a render:
    /// the item waits for a new listing instead of counting as there.
    @Test func staleListingIsNotPresent() async throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:IMG_1.HEIC", .photo, 7_000, "orig")])
        try f.server("Shared/IMG_1.HEIC", size: 7_000, sha: "orig")
        #expect(try await f.count(.isExactly) == 1)
        try await f.database.writer.write { db in
            try db.execute(sql: "UPDATE photo_metadata SET modificationDate = modificationDate + 60 WHERE assetId = 'P0'")
        }
        #expect(try await f.count(.isExactly) == 0)
        #expect(try await f.count(.isNot) == 0)
    }
}

/// Photos items P0… with listed files, and a server source `NAS Home` whose
/// photos are rows of their own in the library, as an index leaves them.
@MainActor
struct OnServerFixture {
    let database: AppDatabase
    let source: String

    init(photos: Int) throws {
        database = try AppDatabase.makeEmpty()
        try MetadataStore(database: database).saveBatch(
            (0..<photos).map { PhotoMarksStoreTests.record("P\($0)", created: 1_700_000_000 + $0) }, cursorAssetId: nil)
        source = try SourceStore(database: database).addServer(name: "NAS Home", connectionId: "C1")
    }

    /// Lists P`n`'s files and their hashes (nil = not hashed yet).
    func photo(_ n: Int, files: [(key: String, role: CopyFile.Role, size: Int64?, sha: String?)]) throws {
        let store = CopyFileStore(database: database)
        try store.saveListing(copyId: "photos:P\(n)", stamp: 1_700_000_000 + n,
                              files: files.map { PhotosFile(fileKey: $0.key, role: $0.role, size: $0.size, stamp: "s") })
        for file in files {
            if let sha = file.sha {
                try store.saveHash(sha, copyId: "photos:P\(n)", fileKey: file.key, origin: .hashed)
            }
        }
    }

    /// A server photo at `path`, with its paired twin if any.
    func server(_ path: String, size: Int64, sha: String?, companion: (path: String, size: Int64, sha: String?)? = nil) throws {
        let id = "server:" + path
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES (?, 1)", arguments: [id])
            try db.execute(sql: """
                INSERT INTO photo_metadata (assetId, mediaType, isFavorite, indexedAt, exifStatus, creationDate)
                VALUES (?, 1, 0, 1, 'indexed', 1700000000)
                """, arguments: [id])
            try db.execute(sql: """
                INSERT INTO photo_copies (id, photoId, sourceId, kind, relativePath, relativePathKey, size, pairedPath)
                VALUES (?, ?, ?, 'server', ?, ?, ?, ?)
                """, arguments: [id, id, source, path, FolderSourceIndexer.pathKey(path), size, companion?.path])
            var files = [CopyFileStore.ListedFile(fileKey: "primary", relativePath: path, size: size, modifiedAt: 1)]
            if let companion {
                files.append(.init(fileKey: "companion", relativePath: companion.path, size: companion.size, modifiedAt: 1))
            }
            try CopyFileStore.saveServerFiles(db, copyId: id, files: files)
            for (key, sha) in [("primary", sha), ("companion", companion?.sha)] {
                guard let sha else { continue }
                try db.execute(sql: "UPDATE copy_files SET sha256 = ? WHERE copyId = ? AND fileKey = ?", arguments: [sha, id, key])
            }
        }
    }

    func rule(_ op: RuleOperator, folder: String? = nil) -> SmartAlbumQuery {
        SmartAlbumQuery(rules: [SmartAlbumRule(field: .source, op: op, text: source, folder: folder)])
    }

    func count(_ op: RuleOperator, folder: String? = nil) async throws -> Int {
        try await LibraryQueries(database: database).count(matching: rule(op, folder: folder))
    }
}
