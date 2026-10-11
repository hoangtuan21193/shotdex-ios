import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.02 §3 — which copy a photo opens from.
@Suite struct CopyOrderTests {
    /// AC-50: photo A is in Photos (original on the device), on T7 and on NAS
    /// Home. It opens from Photos, whose editor saves on Done. With the
    /// Photos copy gone it opens from T7, whose editor keeps its recipe as
    /// it goes — "Edited · Saved", no Done.
    @Test func internalPhotosExternalServerCloud() throws {
        let database = try AppDatabase.makeEmpty()
        let sources = SourceStore(database: database)
        let t7 = try sources.addFolder(name: "T7", bookmark: Data(), includesSubfolders: true, pairsRawAndJpeg: true, kind: "drive")
        let nas = try sources.addServer(name: "NAS Home", connectionId: "C1")
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO photos (id, createdAt) VALUES ('A', 1)")
            for (id, source, kind, asset, path) in [("A-nas", nas, "server", nil, "A.ARW"), ("A-t7", t7, "file", nil, "RAW/A.ARW"),
                                                    ("A-photos", PhotoLibrarySource.id, "photos", "A", nil)] as [(String, String, String, String?, String?)] {
                try db.execute(sql: "INSERT INTO photo_copies (id, photoId, sourceId, kind, photoKitId, relativePath, relativePathKey) VALUES (?, 'A', ?, ?, ?, ?, ?)",
                               arguments: [id, source, kind, asset, path, path?.lowercased()])
            }
        }
        let queries = OpenCopyQueries(database: database)
        let first = try #require(try queries.openCopy(photoId: "A"))
        #expect(first.copyId == "A-photos")
        #expect(first.savesOnDone)

        try MetadataStore(database: database).deleteAssets(ids: ["A"])
        let second = try #require(try queries.openCopy(photoId: "A"))
        #expect(second.copyId == "A-t7")
        #expect(!second.savesOnDone)
        #expect(OpenCopy.autosavedLabel == "Edited · Saved")

        // The rest of the order: a folder on the device beats Photos; iCloud
        // (a Photos item only there, a cloud placeholder) comes after the
        // server; an unplugged drive goes behind everything reachable.
        func candidate(_ id: String, _ kind: String, _ source: String, online: Bool = true, cloud: Bool = false) -> CopyOrder.Candidate {
            CopyOrder.Candidate(copyId: id, kind: kind, sourceKind: source, isOnline: online, isCloudPlaceholder: cloud)
        }
        let order = CopyOrder.sorted([candidate("cloud", "file", "folder", cloud: true), candidate("icloud", "photos", "photos", cloud: true),
                                      candidate("server", "server", "server"),
                                      candidate("drive", "file", "drive", online: false), candidate("photos", "photos", "photos"),
                                      candidate("internal", "file", "folder")]).map(\.copyId)
        #expect(order == ["internal", "photos", "server", "cloud", "icloud", "drive"])
    }
}
