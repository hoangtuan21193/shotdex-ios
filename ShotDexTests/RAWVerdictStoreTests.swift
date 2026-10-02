import Foundation
import GRDB
import Testing
@testable import ShotDex

/// FS-03.04b §5: the verdict table and the pass over the index.
struct RAWVerdictStoreTests {
    typealias F = RAWVerdictFixtures

    @Test func migrationCreatesTheTables() throws {
        let database = try AppDatabase.makeEmpty()
        try database.reader.read { db in
            #expect(try db.tableExists("raw_decoder_verdicts"))
            #expect(try db.tableExists("raw_pair_assets"))
            let columns = try db.columns(in: "raw_decoder_verdicts").map(\.name)
            #expect(columns == ["camera", "osBuild", "verdict", "source", "judgedAt"])
        }
    }

    @Test func recordUpsertsPerCameraAndBuild() throws {
        let store = RAWVerdictStore(database: try AppDatabase.makeEmpty())
        let camera = try #require(RAWCamera(manufacturer: "Sony", model: "ILCE-7M5"))
        try store.record(.unknown, source: nil, for: camera, build: "24A100")
        try store.record(.unreadable, source: .editor, for: camera, build: "24A100")
        try store.record(.readable, source: .list, for: camera, build: "24B200")
        #expect(try store.verdict(for: camera, build: "24A100") == .unreadable)
        #expect(try store.verdict(for: camera, build: "24B200") == .readable)
        #expect(try store.verdicts(build: "24A100") == ["Sony|ILCE-7M5": .unreadable])
    }

    /// Only RAW-named rows bring a camera; a row with no model brings none.
    @Test func indexedRAWCamerasFromRAWFilesOnly() throws {
        let database = try F.database(
            F.rows("n", 2, ext: "NEF", make: "NIKON CORPORATION", model: "NIKON Z 6_2")
            + F.rows("h", 3, ext: "HEIC", make: "Apple", model: "iPhone 15 Pro")
            + F.rows("x", 1, ext: "arw", make: nil, model: nil)
            + F.rows("f", 1, ext: "fff", make: "Hasselblad", model: "X2D 100C")
        )
        let cameras = try RAWVerdictStore(database: database).indexedRAWCameras()
        #expect(Set(cameras.map(\.camera.key)) == ["Nikon|Z 6_2", "Hasselblad|X2D 100C"])
        #expect(cameras.first { $0.camera.manufacturer == "Nikon" }?.exifModel == "NIKON Z 6_2")
    }

    @Test func rawAssetIdsLeaveOutPairs() throws {
        let database = try F.database(F.rows("s", 3, ext: "ARW", make: "SONY", model: "ILCE-7M5"))
        try database.writer.write { try $0.execute(sql: "INSERT INTO raw_pair_assets (assetId) VALUES ('s2')") }
        let camera = try #require(RAWCamera(manufacturer: "Sony", model: "ILCE-7M5"))
        #expect(try RAWVerdictStore(database: database).rawAssetIds(of: camera) == ["s3", "s1"])
    }
}

/// The launch pass (FS-03.04b §2).
struct RAWVerdictPassTests {
    typealias F = RAWVerdictFixtures

    /// AC-1: a NEF from `NIKON Z 6_2`, whose name the list spells "Nikon Z 6 2",
    /// is readable from the list — no file is tried.
    @Test func listedCameraIsReadableWithoutAProbe() async throws {
        let database = try F.database(F.rows("n", 3, ext: "NEF", make: "NIKON CORPORATION", model: "NIKON Z 6_2"))
        let store = RAWVerdictStore(database: database)
        let probe = FakeRAWProbe(models: ["Nikon Z 6 2"], local: ["n1", "n2", "n3"])
        try await RAWVerdictPass(store: store, probe: probe, release: F.release).run()
        let camera = try #require(RAWCamera(manufacturer: "Nikon", model: "Z 6_2"))
        #expect(try store.verdict(for: camera, build: F.release.build) == .readable)
        #expect(probe.asked.isEmpty)
    }
}
