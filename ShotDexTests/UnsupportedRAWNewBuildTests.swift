import Foundation
import Testing
@testable import ShotDex

/// FS-03.04b AC-11: a verdict belongs to the iOS build that made it. After
/// an update the camera is judged again at the next launch.
@MainActor
struct UnsupportedRAWNewBuildTests {
    typealias F = RAWVerdictFixtures

    @Test func updateThatReadsTheCameraClearsTheMarks() async throws {
        let database = try F.database(F.rows("s", 4, ext: "ARW", make: "SONY", model: "ILCE-7M5"))
        let store = RAWVerdictStore(database: database)
        let ids = Set((1...4).map { "s\($0)" })

        // iOS 27.0: refused.
        let old = UnsupportedRAWIndex(store: store, probe: FakeRAWProbe(local: ids), release: OSRelease(build: "24A100", version: "27.0"))
        old.runPass()
        await old.waitForPass()
        #expect(old.assetIds == ids)

        // iOS 27.1: the decoder now reads it, from a file or from its list.
        for probe in [FakeRAWProbe(local: ids, decodes: { _ in true }), FakeRAWProbe(models: ["Sony Alpha ILCE-7M5"])] {
            let new = UnsupportedRAWIndex(store: store, probe: probe, release: OSRelease(build: "24B5\(probe.models.count)", version: "27.1"))
            new.loadIfNeeded()
            new.runPass()
            await new.waitForPass()
            #expect(new.assetIds.isEmpty)
            #expect(new.message(for: "s1") == nil)
        }
        // The old build's row is still there, and still its own.
        #expect(try store.unreadableAssetIds(build: "24A100") == ids)
    }
}
