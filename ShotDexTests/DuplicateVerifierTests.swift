import Foundation
import Testing
@testable import ShotDex

/// The hash nominates, the feature print confirms (2026-11-10): photos the
/// 64-bit hash put together but Vision sees as different must come apart.
struct DuplicateVerifierTests {
    private func photo(_ id: String, bits: UInt64 = 0x0F0F_0F0F_0F0F_0F0F, created: Int = 100) -> HashedPhoto {
        HashedPhoto(assetId: id, hash: PerceptualHash(bits: bits), width: 4000, height: 3000,
                    fileSize: 1_000, creationDate: created, isFavorite: false)
    }

    private func distances(_ table: [Set<String>: Float]) -> (String, String) -> Float? {
        { a, b in table[[a, b]] }
    }

    @Test func lookAlikesVisionSeesAsDifferentComeApart() {
        let group = DuplicateGroup(members: [photo("a"), photo("b"), photo("c")], kind: .similar)
        let result = DuplicateVerifier.verify([group], distance: distances([
            ["a", "b"]: 0.1, ["a", "c"]: 0.9, ["b", "c"]: 0.95,
        ]))
        #expect(result.map { $0.members.map(\.assetId) } == [["a", "b"]])
    }

    /// Complete linkage: c is close to b but not to a, so it does not join.
    @Test func everyMemberMustMatchEveryOther() {
        let group = DuplicateGroup(members: [photo("a"), photo("b"), photo("c")], kind: .similar)
        let result = DuplicateVerifier.verify([group], distance: distances([
            ["a", "b"]: 0.3, ["b", "c"]: 0.3, ["a", "c"]: 0.6,
        ]))
        #expect(result.map { $0.members.map(\.assetId) } == [["a", "b"]])
    }

    /// No print yet: the hash alone proves nothing — two unrelated patterns
    /// were measured with identical hashes. The group waits.
    @Test func withoutPrintsNothingButExactShows() {
        let similar = DuplicateGroup(members: [photo("a"), photo("b")], kind: .similar)
        let exact = DuplicateGroup(members: [photo("c"), photo("d")], kind: .exact)
        let result = DuplicateVerifier.verify([similar, exact]) { _, _ in nil }
        #expect(result.map(\.id) == ["c"])
    }

    @Test func exactCopiesPassUntouched() {
        let group = DuplicateGroup(members: [photo("a"), photo("b")], kind: .exact)
        #expect(DuplicateVerifier.verify([group]) { _, _ in 1.5 } == [group])
    }

    /// A burst is cut where a frame stops matching the one before it, and
    /// a part shorter than a run is no burst.
    @Test func aBurstIsCutAtTheFrameThatChangesScene() {
        let ids = ["a", "b", "c", "d", "e"]
        let group = DuplicateGroup(members: ids.map { photo($0) }, kind: .burst)
        let result = DuplicateVerifier.verify([group], distance: distances([
            ["a", "b"]: 0.3, ["b", "c"]: 0.9, ["c", "d"]: 0.2, ["d", "e"]: 0.3,
        ]))
        #expect(result.map { $0.members.map(\.assetId) } == [["c", "d", "e"]])
    }
}
