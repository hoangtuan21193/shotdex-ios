import Foundation
import Testing
@testable import ShotDex

/// The decision card's rules (FS-06.06 §6–§7, FS-06.06b).
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
        #expect(reasons == [.raw, .biggestFile])
    }

    /// AC-C6: an export of an edit is the keeper; every other copy says in
    /// words what it lacks and where it lives — never "6240×4160".
    @Test func exportOfAnEditIsTheKeeper() {
        var original = photo("K", width: 6240, height: 4160, size: 24_000_000)
        original.originalFilename = "DSC01234.ARW"
        var whatsapp = photo("C1", width: 1600, height: 1067, size: 300_000)
        whatsapp.originalFilename = "IMG-20260101-WA0007.jpg"
        whatsapp.hasCameraEXIF = false
        var export = photo("C2", width: 2048, height: 1365, size: 1_200_000)
        export.software = "Adobe Photoshop Lightroom Classic 14.0"
        let inAlbum = photo("C3", width: 6240, height: 4160, size: 23_000_000)
        let members = [original, whatsapp, export, inAlbum]
        let traits: [String: DuplicateMemberTraits] = ["C3": .init(albums: ["Client"])]

        let keeper = DuplicateReview.keeper(of: members, traits: traits)
        #expect(keeper?.assetId == "C2")
        func caption(_ copy: HashedPhoto) -> [String] {
            DuplicateReview.caption(of: copy, keeper: export, members: members, traits: traits)
        }
        #expect(caption(original) == ["Not edited"])
        #expect(caption(whatsapp) == ["Not edited", "WhatsApp"])
        #expect(caption(inAlbum) == ["Not edited", "In album: Client"])
        for copy in [original, whatsapp, inAlbum] {
            #expect(!caption(copy).joined().contains("×"))
        }
    }

    @Test func captionSaysWhatTheCopyLacksInWords() {
        let keeper = photo("k")
        let traits: [String: DuplicateMemberTraits] = [
            "k": .init(isEdited: true, hasRAW: true, isLive: true),
            "e": .init(isEdited: false, hasRAW: true, isLive: true),
            "r": .init(isEdited: true, hasRAW: false, isLive: true),
            "l": .init(isEdited: true, hasRAW: true, isLive: false),
            "f": .init(isEdited: true, hasRAW: true, isLive: true, isFavorite: true),
            "d": .init(isEdited: true, hasRAW: true, isLive: true),
        ]
        func caption(_ id: String, width: Int = 6000, height: Int = 4000) -> [String] {
            let copy = photo(id, width: width, height: height)
            return DuplicateReview.caption(of: copy, keeper: keeper, members: [keeper, copy], traits: traits)
        }
        #expect(caption("e") == ["Not edited"])
        #expect(caption("r") == ["JPEG only"])
        #expect(caption("l") == ["Still photo"])
        #expect(caption("f") == ["Favorite"])
        #expect(caption("d", width: 3000, height: 2000) == ["Smaller copy"])
        // Nothing worth saying: a clean tile.
        #expect(caption("d") == [])
    }

    /// AC-C7: −1 / 0 / +1 EV 40 s apart — not a bracket, but each copy says
    /// how it was shot differently; what all share is not said.
    @Test func settingsThatDifferAreNamed() {
        func shot(_ id: String, ev: Double) -> HashedPhoto {
            var photo = photo(id)
            photo.exposureBias = ev
            photo.focalLength = 35
            photo.shutterDisplay = "1/60s"
            return photo
        }
        let members = [shot("a", ev: -1), shot("b", ev: 0), shot("c", ev: 1)]
        #expect(DuplicateReview.settings(of: members[0], members: members) == "−1 EV")
        #expect(DuplicateReview.settings(of: members[2], members: members) == "+1 EV")
        var slow = members[2]
        slow.shutterDisplay = "1/15s"
        #expect(DuplicateReview.settings(of: slow, members: [members[0], slow]) == "+1 EV · 1/15 s")
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
        let old = DuplicateGroup(members: [photo("o1", size: 1, created: 100), photo("o2", size: 9_000, created: 100)], kind: .lookAlikes)
        let new = DuplicateGroup(members: [photo("n1", size: 1, created: 900), photo("n2", size: 10, created: 900)], kind: .lookAlikes)
        let free: (DuplicateGroup) -> Int = { group in
            group.members.compactMap(\.fileSize).reduce(0, +) - (group.members.compactMap(\.fileSize).max() ?? 0)
        }
        #expect(DuplicateReview.sorted([new, old], by: .oldest, freeBytes: free).map(\.id) == ["o1", "n1"])
        #expect(DuplicateReview.sorted([old, new], by: .newest, freeBytes: free).map(\.id) == ["n1", "o1"])
        let bigFree = DuplicateGroup(members: [photo("x1", size: 9_000, created: 50), photo("x2", size: 9_000, created: 50)], kind: .lookAlikes)
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

    /// AC-Q2: not scored yet → the file rule, and the chip says so honestly.
    @Test func unscoredGroupSaysBiggestFile() {
        let sharp = photo("P", size: 3_000_000)
        let blurred = photo("Q", size: 5_000_000)
        let members = [sharp, blurred]
        // P is scored, Q is not: the group is not fully scored.
        let scores: [String: DuplicateQualityScore] = ["P": .init(sharpness: 900)]
        let keeper = DuplicateReview.keeper(of: members, traits: [:], scores: scores)
        #expect(keeper?.assetId == "Q")
        let reasons = DuplicateReview.reasons(keeper: blurred, members: members, traits: [:], scores: scores)
        #expect(reasons == [.biggestFile])
        #expect(!reasons.contains(.sharpest))
    }

    /// AC-Q4 (simulated scores): closed eyes lose to open ones before sharpness.
    @Test func eyesClosedRanksBelowEyesOpen() {
        let closed = photo("closed", size: 9_000_000)
        let open = photo("open", size: 1_000_000)
        let scores: [String: DuplicateQualityScore] = [
            "closed": .init(sharpness: 1200, eyesOpen: 0.05, eyeConfidence: 0.95),
            "open": .init(sharpness: 800, eyesOpen: 0.9, eyeConfidence: 0.95),
        ]
        let members = [closed, open]
        #expect(DuplicateReview.keeper(of: members, traits: [:], scores: scores)?.assetId == "open")
        #expect(DuplicateReview.reasons(keeper: open, members: members, traits: [:], scores: scores).first == .eyesOpen)
        #expect(DuplicateReview.weakness(of: closed, keeper: open, traits: [:], scores: scores, groupSharpest: nil) == "Eyes closed")
    }

    /// Below the confidence bar nothing is said about eyes.
    @Test func unsureEyesSayNothing() {
        let a = photo("a", size: 9_000_000)
        let b = photo("b", size: 1_000_000)
        let scores: [String: DuplicateQualityScore] = [
            "a": .init(sharpness: 1000, eyesOpen: 0.05, eyeConfidence: 0.4),
            "b": .init(sharpness: 1000, eyesOpen: 0.9, eyeConfidence: 0.4),
        ]
        #expect(DuplicateReview.keeper(of: [a, b], traits: [:], scores: scores)?.assetId == "a")
        #expect(!DuplicateReview.reasons(keeper: a, members: [a, b], traits: [:], scores: scores).contains(.eyesOpen))
    }

    /// AC-M6: Remove the other … skips a favorite and an album photo.
    @Test func removeOtherSkipsProtected() {
        let members = [photo("K", size: 9), photo("C1", size: 1, favorite: true), photo("C2", size: 1), photo("C3", size: 1)]
        let traits: [String: DuplicateMemberTraits] = ["C2": .init(albums: ["Client"])]
        let removal = DuplicateRemoval.plan(members: members, keeper: members[0], traits: traits)
        #expect(removal.remove == ["C3"])
        #expect(DuplicateProtection.keptLine(removal.kept, namingAlbums: false) == "2 kept: favorite, in album")
    }

    /// AC-S2 (domain): 212 groups, 230 removable photos of which 3 are
    /// protected; 5 unticked groups hold 6 more — 221 get marked.
    @Test func quickCleanNeverPicksProtectedPhotos() {
        var groups: [DuplicateGroup] = []
        var traits: [String: DuplicateMemberTraits] = [:]
        // 194 pairs (194 copies) + 18 triples (36 copies) = 212 groups, 230 copies.
        for index in 0..<212 {
            let copies = index < 194 ? 1 : 2
            let members = [photo("k\(index)", size: 9)] + (0..<copies).map { photo("c\(index)-\($0)", size: 1) }
            groups.append(DuplicateGroup(members: members, kind: .copies))
        }
        // Three protected copies, each in a triple, so their groups stay.
        traits["c194-0"] = .init(isFavorite: true)
        traits["c195-0"] = .init(isEdited: true)
        traits["c196-0"] = .init(albums: ["Client"])
        let items = QuickClean.items(groups: groups, keeper: { $0.members[0] }, traits: traits)
        #expect(items.count == 212)
        #expect(items.flatMap(\.removal.remove).count == 227)
        // Untick five groups holding six other copies: one triple, four pairs.
        let unticked: Set<String> = ["k197", "k5", "k6", "k7", "k8"]
        let selected = QuickClean.selection(items, excluding: unticked)
        #expect(selected.count == 230 - 6 - 3)
        #expect(!selected.contains("c194-0") && !selected.contains("c195-0") && !selected.contains("c196-0"))
        let row = groups[196]
        let removal = DuplicateRemoval.plan(members: row.members, keeper: row.members[0], traits: traits)
        #expect(DuplicateProtection.keptLine(removal.kept, namingAlbums: true) == "1 kept: in album Client")
    }
}
