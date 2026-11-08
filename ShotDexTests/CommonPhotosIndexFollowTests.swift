import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.08 §6 (user 2026-11-08): after a run the index follows the run's
/// own rows — a moved photo's copy changes path, its removed twins go
/// missing, a copied photo gets a copy of the same photo — with no rescan.
@MainActor
struct CommonPhotosIndexFollowTests {
    @Test func movesCopiesAndMissing() throws {
        let f = try OnServerFixture(photos: 0)
        try f.server("Hue/IMG_1.HEIC", size: 100, sha: "a")
        try f.server("Tuan/IMG_1.HEIC", size: 100, sha: "a")
        try f.server("Hue/IMG_2.HEIC", size: 200, sha: "b")
        let moved = CommonPhotosItem(runId: "R", position: 0, sha256: "a", size: 100,
                                     sources: [.init(path: "Hue/IMG_1.HEIC", size: 100, isRemoved: false),
                                               .init(path: "Tuan/IMG_1.HEIC", size: 100, isRemoved: true)],
                                     status: .moved, destinationPath: "Share/IMG_1.HEIC", movedFrom: "Hue/IMG_1.HEIC")
        let copied = CommonPhotosItem(runId: "R", position: 1, sha256: "b", size: 200,
                                      sources: [.init(path: "Hue/IMG_2.HEIC", size: 200)],
                                      status: .copied, destinationPath: "Share/IMG_2.HEIC")
        let skipped = CommonPhotosItem(runId: "R", position: 2, sha256: "c", size: 300, sources: [], status: .skipped)

        let summary = try f.database.writer.write { db in
            try CommonPhotosIndexFollow.apply(db, items: [moved, copied, skipped], connectionId: "C1", folder: "", at: 5_000)
        }

        #expect(summary == .init(moved: 1, copied: 1, missing: 1))
        try f.database.reader.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, photoId, relativePath, missingSince FROM photo_copies WHERE kind = 'server' ORDER BY relativePath")
            let byPath = Dictionary(uniqueKeysWithValues: rows.map { ($0["relativePath"] as String, $0) })
            // The moved copy is the same row at its new path.
            #expect(byPath["Share/IMG_1.HEIC"]?["id"] as String? == "server:Hue/IMG_1.HEIC")
            #expect(byPath["Hue/IMG_1.HEIC"] == nil)
            // Its twin the run removed is missing.
            #expect(byPath["Tuan/IMG_1.HEIC"]?["missingSince"] as Int? == 5_000)
            // The copy is a new row of the same photo, its hash known.
            let copy = try #require(byPath["Share/IMG_2.HEIC"])
            #expect(copy["photoId"] as String? == "server:Hue/IMG_2.HEIC")
            #expect(try String.fetchOne(db, sql: "SELECT sha256 FROM copy_files WHERE copyId = ?", arguments: [copy["id"] as String]) == "b")
        }
    }

    /// Paths from the share's root against a source under the connection's
    /// Folder; one outside it is left for the next read.
    @Test func relativeToFolder() {
        #expect(CommonPhotosIndexFollow.relative("photos/Share/IMG.HEIC", to: "photos") == "Share/IMG.HEIC")
        #expect(CommonPhotosIndexFollow.relative("/photos/Share/IMG.HEIC", to: "/photos/") == "Share/IMG.HEIC")
        #expect(CommonPhotosIndexFollow.relative("other/IMG.HEIC", to: "photos") == nil)
        #expect(CommonPhotosIndexFollow.relative("Share/IMG.HEIC", to: "") == "Share/IMG.HEIC")
    }
}
