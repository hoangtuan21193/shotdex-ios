import Foundation
import Testing
@testable import ShotDex

/// The v2 decision card's rules (FS-06.06 §7, FS-06.06b AC-5, AC-D1…D6).
struct DuplicateReviewTests {

    private func photo(
        _ id: String,
        width: Int? = 6000,
        height: Int? = 4000,
        size: Int? = 10_000_000,
        created: Int? = 1_700_000_000,
        favorite: Bool = false
    ) -> HashedPhoto {
        HashedPhoto(
            assetId: id,
            hash: PerceptualHash(bits: 0),
            width: width,
            height: height,
            fileSize: size,
            creationDate: created,
            isFavorite: favorite
        )
    }

    /// AC-5: edited beats favourite beats file size beats pixels.
    @Test func keeperIsEditedThenFavoriteThenLargerFile() {
        let a = photo("a", size: 3_200_000)
        let b = photo("b", size: 4_000_000, favorite: true)
        let c = photo("c", size: 4_500_000)
        let edited: [String: DuplicateMemberTraits] = ["a": .init(isEdited: true)]
        #expect(DuplicateReview.keeper(of: [c, b, a], traits: edited)?.assetId == "a")
        #expect(DuplicateReview.keeper(of: [c, b, a], traits: [:])?.assetId == "b")
        let plainB = photo("b", size: 4_000_000)
        #expect(DuplicateReview.keeper(of: [plainB, a, c], traits: [:])?.assetId == "c")
    }

    @Test func keeperTieOnSizeGoesToMorePixels() {
        let small = photo("s", width: 3000, height: 2000, size: 5_000_000)
        let big = photo("b", width: 6000, height: 4000, size: 5_000_000)
        #expect(DuplicateReview.keeper(of: [small, big], traits: [:])?.assetId == "b")
    }

    /// A reason chip only appears when it sets the keeper apart.
    @Test func reasonsOnlyNameWhatTheCopiesLack() {
        let keeper = photo("k", size: 18_900_000)
        let copy = photo("c", size: 4_400_000)
        let traits: [String: DuplicateMemberTraits] = [
            "k": .init(isEdited: true, hasRAW: true),
            "c": .init(isEdited: true, hasRAW: false),
        ]
        let reasons = DuplicateReview.reasons(keeper: keeper, members: [keeper, copy], traits: traits)
        #expect(reasons == [.raw, .largest])
    }

    @Test func differenceSaysWhatTheCopyLacksFirst() {
        let keeper = photo("k")
        let traits: [String: DuplicateMemberTraits] = [
            "k": .init(isEdited: true, hasRAW: true, isLive: true, isFavorite: true),
            "e": .init(isEdited: false, hasRAW: true, isLive: true, isFavorite: true),
            "r": .init(isEdited: true, hasRAW: false, isLive: true, isFavorite: true),
            "f": .init(isEdited: true, hasRAW: true, isLive: true, isFavorite: false),
            "l": .init(isEdited: true, hasRAW: true, isLive: false, isFavorite: true),
            "d": .init(isEdited: true, hasRAW: true, isLive: true, isFavorite: true),
        ]
        func diff(_ id: String, width: Int = 6000, height: Int = 4000) -> String {
            DuplicateReview.difference(of: photo(id, width: width, height: height), from: keeper, traits: traits)
        }
        #expect(diff("e") == "Not edited")
        #expect(diff("r") == "JPEG only")
        #expect(diff("f") == "Not favorite")
        #expect(diff("l") == "Still photo")
        #expect(diff("d", width: 3120, height: 2080) == "3120×2080")
    }

    @Test func freeBytesLeaveTheKeeperOut() {
        let members = [photo("k", size: 18_900_000), photo("a", size: 4_400_000), photo("b", size: 2_200_000)]
        #expect(DuplicateReview.freeBytes(members: members, keeper: members[0]) == 6_600_000)
    }

    @Test func spanReadsSecondsMinutesHoursDays() {
        let base = 1_700_000_000
        #expect(DuplicateReview.spanText([photo("a", created: base), photo("b", created: base + 4)]) == "4 s apart")
        #expect(DuplicateReview.spanText([photo("a", created: base), photo("b", created: base + 180)]) == "3 min apart")
        #expect(DuplicateReview.spanText([photo("a", created: base), photo("b", created: base + 7200)]) == "2 h apart")
        #expect(DuplicateReview.spanText([photo("a", created: base), photo("b", created: base + 3 * 86_400)]) == "3 days apart")
        #expect(DuplicateReview.spanText([photo("a", created: base), photo("b", created: nil)]) == nil)
        #expect(DuplicateReview.spanText([photo("a", created: base), photo("b", created: base)]) == nil)
    }

    @Test func sortOrdersBySpaceThenDate() {
        let old = DuplicateGroup(members: [photo("o1", size: 1, created: 100), photo("o2", size: 9_000, created: 100)])
        let new = DuplicateGroup(members: [photo("n1", size: 1, created: 900), photo("n2", size: 10, created: 900)])
        let free: (DuplicateGroup) -> Int = { group in
            group.members.compactMap(\.fileSize).reduce(0, +) - (group.members.compactMap(\.fileSize).max() ?? 0)
        }
        #expect(DuplicateReview.sorted([new, old], by: .oldest, freeBytes: free).map(\.id) == ["o1", "n1"])
        #expect(DuplicateReview.sorted([old, new], by: .newest, freeBytes: free).map(\.id) == ["n1", "o1"])
        let bigFree = DuplicateGroup(members: [photo("x1", size: 9_000, created: 50), photo("x2", size: 9_000, created: 50)])
        #expect(DuplicateReview.sorted([new, bigFree], by: .mostSpace, freeBytes: free).map(\.id) == ["x1", "n1"])
    }

    /// Card geometry on the four boards: iPhone and Duo cover 2 copies per
    /// row, iPad 3, keeper = two tiles + one gap.
    @Test func cardMetricsMatchTheBoards() {
        let phone = DuplicateCardMetrics(innerWidth: 370 - 24, copyColumns: 2)
        #expect(phone.tile == 83)
        #expect(phone.keeper == 170)
        let pinched = DuplicateCardMetrics(innerWidth: 346, copyColumns: 3)
        #expect(pinched.tile == 66)
        // iPad landscape: 1344pt content → 3 cards of 437pt.
        #expect(DuplicateCardMetrics.cardColumns(contentWidth: 1344, isRegular: true) == 3)
        #expect(Int(DuplicateCardMetrics.cardWidth(contentWidth: 1344, columns: 3)) == 437)
        // iPad portrait 1000 → 2 × 492; Duo inner 835 → 2 × 409.5.
        #expect(DuplicateCardMetrics.cardColumns(contentWidth: 1000, isRegular: true) == 2)
        #expect(DuplicateCardMetrics.cardColumns(contentWidth: 835, isRegular: true) == 2)
        #expect(DuplicateCardMetrics.cardColumns(contentWidth: 370, isRegular: false) == 1)
        let ipad = DuplicateCardMetrics(innerWidth: 437 - 24, copyColumns: 3)
        #expect(ipad.tile == 79)
    }

    /// Board `PH_DuplicatesLargeGroup`: keeper 2×2 cells, copies beside it
    /// then in full rows below, every copy square.
    @Test func aBigGroupFillsTheCardUnderTheKeeper() {
        let metrics = DuplicateCardMetrics(innerWidth: 346, copyColumns: 2)
        #expect(metrics.keeper == metrics.tile * 2 + DuplicateCardMetrics.copyGap)
        let origins = metrics.copyOrigins(count: 7)
        let step = metrics.tile + DuplicateCardMetrics.copyGap
        // Four beside the keeper, two rows of two.
        #expect(origins[0] == CGPoint(x: metrics.keeper + 4, y: 0))
        #expect(origins[3] == CGPoint(x: metrics.keeper + 4 + step, y: step))
        // Then a full-width row under it, from the left edge.
        #expect(origins[4] == CGPoint(x: 0, y: metrics.keeper + 4))
        #expect(origins[6] == CGPoint(x: 2 * step, y: metrics.keeper + 4))
        #expect(metrics.gridHeight(copyCount: 7) == metrics.keeper + step)
        // Three copies stay beside the keeper: no row below.
        #expect(metrics.gridHeight(copyCount: 3) == metrics.keeper)
        // Nothing spills past the card.
        #expect(origins.allSatisfy { $0.x + metrics.tile <= 346 })
    }
}
