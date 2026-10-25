import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-19.07 §3, phase 2: a Photos item and its byte-identical server copy
/// show as one photo — without the check ever writing to the server.
extension PhotoIdentityMergeTests {
    /// AC-106: one pass of the check folds 10 server photos into their
    /// Photos items; not one sidecar is queued for the NAS.
    @MainActor @Test func checkMergeWritesNoSidecar() async throws {
        let f = try Self.tenOnServer()
        let database = f.database
        let check = OnServerCheck(environment: .init(
            serverSources: { [(id: f.source, name: "NAS Home", connectionId: "C1")] },
            jobRules: { _ in [] },
            conditions: { (false, true) },
            list: { _ in true },
            hashServer: { _, _, _ in .init() },
            hashPhotos: { _ in .init() },
            merge: { try OnServerMergePass(database: database).run() }
        ))
        await check.run()
        let counts = try await database.reader.read { db in
            (aliases: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_aliases") ?? -1,
             sidecars: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_sidecar") ?? -1,
             shown: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_metadata") ?? -1,
             owners: try String.fetchAll(db, sql: "SELECT DISTINCT photoId FROM photo_copies WHERE kind = 'server' ORDER BY photoId"))
        }
        #expect(counts.aliases == 10)
        #expect(counts.sidecars == 0)
        // One tile per picture, under the Photos asset's id.
        #expect(counts.shown == 10)
        #expect(counts.owners == (0..<10).map { "P\($0)" }.sorted())
        // The album does not depend on the merge.
        #expect(try await f.count(.isExactly) == 10)
        // A second pass has nothing to fold.
        #expect(try OnServerMergePass(database: database).run() == 0)
    }

    /// AC-98 with the merge: deleting goes to the Photos copy alone; the
    /// photo stays in the library through its NAS copy.
    @MainActor @Test func deletingMergedKeepsServerCopy() async throws {
        let f = try Self.tenOnServer()
        try OnServerMergePass(database: f.database).run()
        let queries = DeletionTargetQueries(database: f.database, hasTrash: { _ in false })
        // Every photo's first copy is its Photos asset: the plain Photos
        // delete runs, never the source path that hides a server copy.
        #expect(try queries.request(photoIds: ["P0", "P1"], selection: .photos) == nil)
        try MetadataStore(database: f.database).deleteAssets(ids: ["P0"])
        #expect(try queries.stillShown(photoIds: ["P0"]) == ["P0"])
        let hidden = try await f.database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM photo_copies WHERE kind = 'server' AND (isHidden = 1 OR missingSince IS NOT NULL)")
        }
        #expect(hidden == 0)
    }

    /// A server photo that is only part of a Photos item — the HEIC of a
    /// Live Photo without its movie — is not folded in.
    @MainActor @Test func partialMatchStaysApart() throws {
        let f = try OnServerFixture(photos: 1)
        try f.photo(0, files: [("1:IMG_1.HEIC", .photo, 2_000, "heic"), ("9:IMG_1.MOV", .pairedVideo, 3_000, "mov")])
        // The NAS pair is HEIC + a different movie.
        try f.server("Shared/IMG_1.HEIC", size: 2_000, sha: "heic", companion: ("Shared/IMG_1.MOV", 3_000, "other"))
        #expect(try OnServerMergePass(database: f.database).run() == 0)
    }

    /// Ten Photos items, each with its file on the NAS as a photo of its own.
    @MainActor private static func tenOnServer() throws -> OnServerFixture {
        let f = try OnServerFixture(photos: 10)
        for n in 0..<10 {
            try f.photo(n, files: [("1:IMG_\(n).HEIC", .photo, 1_000 + Int64(n), "sha\(n)")])
            try f.server("Shared/IMG_\(n).HEIC", size: 1_000 + Int64(n), sha: "sha\(n)")
        }
        return f
    }
}
