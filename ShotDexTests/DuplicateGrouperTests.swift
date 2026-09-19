import Foundation
import Testing
@testable import ShotDex

struct DuplicateGrouperTests {

    private func photo(
        _ id: String,
        bits: UInt64,
        width: Int? = 6000,
        height: Int? = 4000,
        size: Int? = 10_000_000,
        created: Int? = 1_700_000_000,
        favorite: Bool = false
    ) -> HashedPhoto {
        HashedPhoto(
            assetId: id,
            hash: PerceptualHash(bits: bits),
            width: width,
            height: height,
            fileSize: size,
            creationDate: created,
            isFavorite: favorite
        )
    }

    @Test func singletonsAreNotGroups() {
        let groups = DuplicateGrouper.groups(
            from: [photo("a", bits: 1), photo("b", bits: 0xFFFF_FFFF)],
            strictness: .similar
        )
        #expect(groups.isEmpty)
    }

    /// Named modes rather than `allCases`: `.series` answers a different
    /// question and deliberately does not group a pair (see
    /// `DuplicateSeriesTests`), so sweeping every case here would assert the
    /// wrong thing about it.
    @Test func identicalHashesGroupInBothDuplicateModes() {
        // "c" is 32 bits away from the pair — far outside the similar threshold.
        let photos = [photo("a", bits: 42), photo("b", bits: 42), photo("c", bits: 42 ^ 0xFFFF_FFFF_0000_0000)]
        for strictness in [DuplicateStrictness.exact, .similar] {
            let groups = DuplicateGrouper.groups(from: photos, strictness: strictness)
            #expect(groups.count == 1)
            #expect(Set(groups[0].members.map(\.assetId)) == ["a", "b"])
        }
    }

    @Test func exactModeSeparatesDifferentDimensions() {
        let photos = [photo("a", bits: 42), photo("b", bits: 42, width: 2000, height: 1333)]
        #expect(DuplicateGrouper.groups(from: photos, strictness: .exact).isEmpty)
        #expect(DuplicateGrouper.groups(from: photos, strictness: .similar).count == 1)
    }

    @Test func similarModeGroupsWithinThreshold() {
        let base: UInt64 = 0x0123_4567_89AB_CDEF
        // Flip 10 bits spread across bytes — within threshold.
        let tenBitsAway = base ^ 0x0101_0101_0101_0303
        // Flip 11 *other* bits — outside, and 21 bits from `tenBitsAway` so
        // it cannot chain in through "b".
        let elevenBitsAway = base ^ 0x0202_0202_0202_0C1C
        #expect((base ^ tenBitsAway).nonzeroBitCount == 10)
        #expect((base ^ elevenBitsAway).nonzeroBitCount == 11)
        #expect((tenBitsAway ^ elevenBitsAway).nonzeroBitCount == 21)

        let groups = DuplicateGrouper.groups(
            from: [photo("a", bits: base), photo("b", bits: tenBitsAway), photo("c", bits: elevenBitsAway)],
            strictness: .similar
        )
        #expect(groups.count == 1)
        #expect(Set(groups[0].members.map(\.assetId)) == ["a", "b"])
        #expect(DuplicateGrouper.groups(
            from: [photo("a", bits: base), photo("b", bits: tenBitsAway)],
            strictness: .exact
        ).isEmpty)
    }

    @Test func nearMatchesChainIntoOneGroup() {
        // a~b and b~c but a and c are 20 bits apart: one connected component.
        let a: UInt64 = 0
        let b: UInt64 = 0x03FF          // 10 bits
        let c: UInt64 = 0xF_FFFF        // 20 bits
        #expect((a ^ c).nonzeroBitCount == 20)
        let groups = DuplicateGrouper.groups(
            from: [photo("a", bits: a), photo("b", bits: b), photo("c", bits: c)],
            strictness: .similar
        )
        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
    }

    @Test func membersAreOrderedBestFirst() {
        let photos = [
            photo("small", bits: 1, width: 2000, height: 1333, size: 1_000_000),
            photo("lighter", bits: 1, size: 8_000_000, created: 1_700_000_100),
            photo("favorite", bits: 1, size: 8_000_000, created: 1_700_000_100, favorite: true),
            photo("heavy", bits: 1, size: 12_000_000, created: 1_700_000_200),
            photo("older", bits: 1, size: 8_000_000, created: 1_600_000_000),
        ]
        let groups = DuplicateGrouper.groups(from: photos, strictness: .exact)
        // Exact mode keys on dimensions too, so "small" stays out.
        #expect(groups.count == 1)
        #expect(groups[0].members.map(\.assetId) == ["heavy", "favorite", "older", "lighter"])
        #expect(groups[0].reclaimableBytes == 24_000_000)
    }

    @Test func groupsAreOrderedNewestFirst() {
        let photos = [
            photo("old1", bits: 1, created: 100), photo("old2", bits: 1, created: 200),
            photo("new1", bits: 0xFFFF_0000, created: 900), photo("new2", bits: 0xFFFF_0000, created: 800),
        ]
        let groups = DuplicateGrouper.groups(from: photos, strictness: .similar)
        #expect(groups.map(\.id) == ["new2", "old1"])
    }

    @Test func manyIdenticalHashesStayCheap() {
        // 5 000 blank frames plus one near neighbour: the near search runs over
        // distinct hashes only, so this must finish quickly and group everything.
        var photos = (0..<5000).map { photo("blank\($0)", bits: 0) }
        photos.append(photo("near", bits: 0b111))
        let groups = DuplicateGrouper.groups(from: photos, strictness: .similar)
        #expect(groups.count == 1)
        #expect(groups[0].count == 5001)
    }
}
