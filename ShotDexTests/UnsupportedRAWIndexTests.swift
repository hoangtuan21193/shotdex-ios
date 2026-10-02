import Foundation
import Photos
import Testing
@testable import ShotDex

/// FS-03.04b AC-2: the second step (a file on the device) and the set of
/// photos the grid marks.
@MainActor
struct UnsupportedRAWIndexTests {
    typealias F = RAWVerdictFixtures

    func index(_ rows: [PhotoMetadata], probe: FakeRAWProbe) throws -> UnsupportedRAWIndex {
        UnsupportedRAWIndex(store: RAWVerdictStore(database: try F.database(rows)), probe: probe, release: F.release)
    }

    /// AC-2: 8 ARWs on the device of a camera the list doesn't name, the
    /// decoder refusing, and 5 HEICs → exactly the 8 are marked.
    @Test func refusedCameraMarksItsRAWsOnly() async throws {
        let arws = F.rows("s", 8, ext: "ARW", make: "SONY", model: "ILCE-7M5")
        let heics = F.rows("h", 5, ext: "HEIC", make: "Apple", model: "iPhone 17 Pro")
        let probe = FakeRAWProbe(models: ["Sony Alpha ILCE-7M4"], local: Set(arws.map(\.assetId)))
        let index = try index(arws + heics, probe: probe)
        index.runPass()
        await index.waitForPass()
        #expect(index.assetIds == Set(arws.map(\.assetId)))
        #expect(index.version == 1)
        // Two files were tried before the camera was called unreadable (Q5).
        #expect(probe.asked == ["s8", "s7"])
    }

    /// Q5: one odd file does not mark the camera — the second decodes.
    @Test func secondFileDecodingKeepsTheCameraReadable() async throws {
        let arws = F.rows("s", 8, ext: "ARW", make: "SONY", model: "ILCE-7M5")
        let probe = FakeRAWProbe(local: Set(arws.map(\.assetId)), decodes: { $0 != "s8" })
        let index = try index(arws, probe: probe)
        index.runPass()
        await index.waitForPass()
        #expect(index.assetIds.isEmpty)
        let camera = try #require(RAWCamera(manufacturer: "Sony", model: "ILCE-7M5"))
        #expect(try index.store.verdict(for: camera, build: F.release.build) == .readable)
    }

    /// A camera with exactly one file on the device: one refusal is enough.
    @Test func onlyLocalFileRefusedMarks() async throws {
        let arws = F.rows("s", 3, ext: "ARW", make: "SONY", model: "ILCE-7M5")
        let index = try index(arws, probe: FakeRAWProbe(local: ["s1"]))
        index.runPass()
        await index.waitForPass()
        #expect(index.assetIds == ["s1", "s2", "s3"])
    }

    /// A RAW-named photo with a JPEG twin is a pair: never marked (M3).
    @Test func pairKeptAsRAWIsNotMarked() async throws {
        final class TwinProbe: RAWDecoderProbing, @unchecked Sendable {
            func supportedCameraModels() -> [String] { [] }
            func localFileDecodes(assetId: String) async -> Bool? { false }
            func renderedTwinIds(among assetIds: [String]) async -> Set<String> { Set(assetIds).intersection(["s2"]) }
        }
        let arws = F.rows("s", 3, ext: "ARW", make: "SONY", model: "ILCE-7M5")
        let index = UnsupportedRAWIndex(
            store: RAWVerdictStore(database: try F.database(arws)), probe: TwinProbe(), release: F.release
        )
        index.runPass()
        await index.waitForPass()
        #expect(index.assetIds == ["s1", "s3"])
    }

    /// The verdict is this build's: rows of another build mark nothing.
    @Test func otherBuildsVerdictIsIgnored() async throws {
        let arws = F.rows("s", 2, ext: "ARW", make: "SONY", model: "ILCE-7M5")
        let store = RAWVerdictStore(database: try F.database(arws))
        let camera = try #require(RAWCamera(manufacturer: "Sony", model: "ILCE-7M5"))
        try store.record(.unreadable, source: .file, for: camera, build: "23F77")
        #expect(try store.unreadableAssetIds(build: F.release.build).isEmpty)
        #expect(try store.unreadableAssetIds(build: "23F77") == ["s1", "s2"])
    }
}

/// The device's probe against the photos M3 left in the simulator's
/// library: `M3D.RAF` is a RAF whose camera the decoder doesn't know,
/// `M3C.ARW` a readable ARW, `M3H` a JPEG + that RAF, `M3B` an ARW kept as
/// the original with its JPEG.
@MainActor
struct SystemRAWDecoderProbeTests {
    nonisolated static func asset(named name: String) -> String? {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return nil }
        var found: String?
        PHAsset.fetchAssets(with: .image, options: nil).enumerateObjects { asset, _, stop in
            if PHAssetResource.assetResources(for: asset).contains(where: { $0.originalFilename == name }) {
                found = asset.localIdentifier
                stop.pointee = true
            }
        }
        return found
    }

    nonisolated static let hasM3 = asset(named: "M3D.RAF") != nil

    @Test(.enabled(if: hasM3, "needs the M3 photos in the simulator's library (FS-03.04b plan)"))
    func decodesOnlyWhatTheDecoderReads() async throws {
        let probe = SystemRAWDecoderProbe()
        let unsupported = try #require(Self.asset(named: "M3D.RAF"))
        let readable = try #require(Self.asset(named: "M3C.ARW"))
        #expect(await probe.localFileDecodes(assetId: unsupported) == false)
        #expect(await probe.localFileDecodes(assetId: readable) == true)
    }

    @Test(.enabled(if: hasM3, "needs the M3 photos in the simulator's library (FS-03.04b plan)"))
    func findsPairsWhicheverFileIsTheOriginal() async throws {
        let probe = SystemRAWDecoderProbe()
        let ids = try ["M3D.RAF", "M3B.ARW", "M3H.JPG", "M3C.ARW"].map { try #require(Self.asset(named: $0)) }
        #expect(await probe.renderedTwinIds(among: ids) == [ids[1], ids[2]])
    }
}
