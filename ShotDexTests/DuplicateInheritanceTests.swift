import Foundation
import Testing
@testable import ShotDex

/// FS-06.06b §2 — what the kept photo takes from the copies deleted beside it.
struct DuplicateInheritanceTests {
    private func photo(_ id: String, created: Int = 1_700_000_000, favorite: Bool = false) -> HashedPhoto {
        HashedPhoto(assetId: id, hash: PerceptualHash(bits: 0), width: 6000, height: 4000, fileSize: 1,
                    creationDate: created, isFavorite: favorite)
    }

    /// AC-D5 (plan): K takes C's album and favorite; Copies take the date.
    @Test func copiesKeeperTakesAlbumFavoriteAndDate() {
        let group = DuplicateGroup(members: [photo("K"), photo("C", created: 1_600_000_000, favorite: true)], kind: .exact)
        let traits: [String: DuplicateMemberTraits] = [
            "C": .init(isFavorite: true, albums: ["Client"], albumIds: ["album-client"]),
        ]
        let plans = DuplicateInheritance.plan(groups: [group], deleting: ["C"], traits: traits)
        #expect(plans == [DuplicateInheritance(keeperId: "K", albumIds: ["album-client"], favorite: true,
                                                donorIds: ["C"], takesEarliestDate: true)])
    }

    /// AC-D6 (plan): a look-alike keeps its own date.
    @Test func lookAlikeKeeperKeepsItsDate() {
        let group = DuplicateGroup(members: [photo("K"), photo("C", favorite: true)], kind: .similar)
        let plan = DuplicateInheritance.plan(groups: [group], deleting: ["C"], traits: [:]).first
        #expect(plan?.takesEarliestDate == false)
        #expect(plan?.favorite == true)
    }

    @Test func twoKeptPhotosInheritNothing() {
        let group = DuplicateGroup(members: [photo("A"), photo("B"), photo("C", favorite: true)], kind: .burst)
        #expect(DuplicateInheritance.plan(groups: [group], deleting: ["C"], traits: [:]).isEmpty)
    }

    @Test func albumTheKeeperIsAlreadyInIsNotAddedTwice() {
        let group = DuplicateGroup(members: [photo("K"), photo("C")], kind: .exact)
        let traits: [String: DuplicateMemberTraits] = [
            "K": .init(albums: ["Client"], albumIds: ["a1"]),
            "C": .init(albums: ["Client", "Trip"], albumIds: ["a1", "a2"]),
        ]
        #expect(DuplicateInheritance.plan(groups: [group], deleting: ["C"], traits: traits).first?.albumIds == ["a2"])
    }
}
