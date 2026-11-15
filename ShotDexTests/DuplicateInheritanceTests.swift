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

/// FS-06.06b §2 (2026-11-15, after Immich): the kept photo takes the highest
/// rating in the group, written where every other rating goes.
@MainActor
struct DuplicateRatingInheritanceTests {
    private func photo(_ id: String) -> HashedPhoto {
        HashedPhoto(assetId: id, hash: PerceptualHash(bits: 0), width: 6000, height: 4000, fileSize: 1,
                    creationDate: 1_700_000_000, isFavorite: false)
    }

    private var group: DuplicateGroup {
        DuplicateGroup(members: [photo("K"), photo("C1"), photo("C2")], kind: .exact)
    }

    /// AC-D9 (plan): K 2★, C1 5★, C2 unrated → K takes 5.
    @Test func keeperTakesTheHighestRating() {
        let plan = DuplicateInheritance.plan(groups: [group], deleting: ["C1", "C2"], traits: [:],
                                             ratings: ["K": 2, "C1": 5, "C2": 0]).first
        #expect(plan?.rating == 5)
        #expect(plan?.isEmpty == false)
    }

    /// A keeper rated as high or higher keeps its own; nothing to write.
    @Test func higherRatedKeeperIsLeftAlone() {
        let plans = DuplicateInheritance.plan(groups: [group], deleting: ["C1", "C2"], traits: [:],
                                              ratings: ["K": 5, "C1": 3])
        #expect(plans.first?.rating == nil)
    }

    /// AC-D9: on iOS 27 the stars go to Photos in one write.
    @Test func ratingGoesToPhotosOnIOS27() async throws {
        let store = PhotoMarksStore(database: try AppDatabase.makeEmpty())
        let writer = FakePropertyWriter(modificationDate: 1_700_000_000)
        let marks = PhotoMarks(store: store, ratingWriter: writer, readPhotosRatings: { _ in ["K": 2, "C1": 5] })
        let ratings = await marks.ratings(for: ["K", "C1", "C2"])
        #expect(ratings == ["K": 2, "C1": 5, "C2": 0])
        let plans = DuplicateInheritance.plan(groups: [group], deleting: ["C1", "C2"], traits: [:], ratings: ratings)
        #expect(await DuplicateInheritance.applyRatings(plans, marks: marks).isEmpty)
        #expect(writer.ratings == ["K": 5])
        #expect(writer.blocks == [1])
    }

    /// Two groups inheriting different stars are still one write to Photos.
    @Test func severalKeepersAreOneWrite() async throws {
        let store = PhotoMarksStore(database: try AppDatabase.makeEmpty())
        let writer = FakePropertyWriter(modificationDate: 1_700_000_000)
        let marks = PhotoMarks(store: store, ratingWriter: writer)
        let plans = [
            DuplicateInheritance(keeperId: "K1", albumIds: [], favorite: false, donorIds: ["a"], takesEarliestDate: true, rating: 5),
            DuplicateInheritance(keeperId: "K2", albumIds: [], favorite: false, donorIds: ["b"], takesEarliestDate: true, rating: 3),
        ]
        #expect(await DuplicateInheritance.applyRatings(plans, marks: marks).isEmpty)
        #expect(writer.ratings == ["K1": 5, "K2": 3])
        #expect(writer.blocks == [2])
    }

    /// The write fails: the count reaches the banner, the keeper keeps its
    /// old stars, nothing claims they moved.
    @Test func failedWriteIsCountedForTheBanner() async throws {
        let store = PhotoMarksStore(database: try AppDatabase.makeEmpty())
        let writer = FakePropertyWriter(modificationDate: 1_700_000_000)
        writer.failure = CocoaError(.fileWriteUnknown)
        let marks = PhotoMarks(store: store, ratingWriter: writer, readPhotosRatings: { _ in ["K": 2] })
        let plans = [DuplicateInheritance(keeperId: "K", albumIds: [], favorite: false, donorIds: ["C"],
                                          takesEarliestDate: true, rating: 5)]
        #expect(await DuplicateInheritance.applyRatings(plans, marks: marks) == ["K"])
        #expect(marks.rating(for: "K", photosRating: 2) == 2)
    }

    /// AC-D10: below iOS 27 the stars wait in the pending queue, like any
    /// rating set there.
    @Test func belowIOS27RatingGoesToThePendingQueue() async throws {
        let store = PhotoMarksStore(database: try AppDatabase.makeEmpty())
        let marks = PhotoMarks(store: store)
        await marks.setRating(2, ids: ["K"])
        await marks.setRating(5, ids: ["C1"])
        let ratings = await marks.ratings(for: ["K", "C1", "C2"])
        let plans = DuplicateInheritance.plan(groups: [group], deleting: ["C1", "C2"], traits: [:], ratings: ratings)
        #expect(await DuplicateInheritance.applyRatings(plans, marks: marks).isEmpty)
        #expect(try store.allPendingRatings()["K"] == 5)
        #expect(marks.rating(for: "K") == 5)
    }
}

/// FS-06.06b §2 (2026-11-15, after Immich): caption lines and keywords of
/// the deleted copies move to the kept photo (iOS 27).
struct DuplicateCaptionKeywordInheritanceTests {
    /// AC-D11: lines kept in order, repeats dropped; keywords merged case-
    /// insensitively, the keeper's spelling winning.
    @Test func captionLinesAndKeywordsAreMerged() {
        let keeper = CaptionKeywords(caption: "Hội An\nfilm", keywords: ["Travel"])
        let donor = CaptionKeywords(caption: "film\nKodak Gold", keywords: ["travel", "Kodak"])
        let change = DuplicateInheritance.captionKeywordChange(keeper: keeper, donors: [donor])
        #expect(change.caption == .set("Hội An\nfilm\nKodak Gold"))
        #expect(change.add == ["Kodak"])
        #expect(change.remove.isEmpty)
        #expect(change.applied(to: keeper) == CaptionKeywords(caption: "Hội An\nfilm\nKodak Gold", keywords: ["Travel", "Kodak"]))
    }

    /// Nothing new on the copies: no write at all.
    @Test func nothingNewIsNoChange() {
        let keeper = CaptionKeywords(caption: "Hội An", keywords: ["Travel"])
        let donor = CaptionKeywords(caption: "  Hội An  ", keywords: ["TRAVEL"])
        #expect(DuplicateInheritance.captionKeywordChange(keeper: keeper, donors: [donor]).isEmpty)
        #expect(DuplicateInheritance.captionKeywordChange(keeper: .empty, donors: [.empty]).isEmpty)
    }

    /// The keeper's own caption is never rewritten: repeated lines, odd
    /// spacing and all stay; only new lines are appended.
    @Test func keeperCaptionIsAppendedToNeverRewritten() {
        let keeper = CaptionKeywords(caption: "A\nA  ", keywords: [])
        #expect(DuplicateInheritance.captionKeywordChange(
            keeper: keeper, donors: [CaptionKeywords(caption: "A", keywords: ["x"])]).caption == .untouched)
        #expect(DuplicateInheritance.captionKeywordChange(
            keeper: keeper, donors: [CaptionKeywords(caption: "B")]).caption == .set("A\nA  \nB"))
        #expect(DuplicateInheritance.captionKeywordChange(
            keeper: .empty, donors: [CaptionKeywords(keywords: [" Kodak "])]).add == ["Kodak"])
    }

    /// A keeper with no caption takes the copies' lines.
    @Test func emptyKeeperTakesTheCopiesCaption() {
        let change = DuplicateInheritance.captionKeywordChange(
            keeper: .empty, donors: [CaptionKeywords(caption: "Dawn"), CaptionKeywords(caption: "Dawn\nTripod")])
        #expect(change.caption == .set("Dawn\nTripod"))
    }

    /// AC-D12: Photos refuses the write — every kept photo it covered is
    /// counted for the banner; a refused id alone counts one.
    @Test func failedOrRefusedWritesAreCounted() async {
        let changes: [String: CaptionKeywordChange] = ["K1": .init(add: ["a"]), "K2": .init(add: ["b"])]
        let failed = await DuplicateInheritance.applyCaptionKeywords(changes) { _ in throw CocoaError(.fileWriteUnknown) }
        #expect(failed == ["K1", "K2"])
        let refused = await DuplicateInheritance.applyCaptionKeywords(changes) { _ in
            PropertyWriteResult(dates: [:], refused: ["K2"])
        }
        #expect(refused == ["K2"])
        #expect(await DuplicateInheritance.applyCaptionKeywords([:]) { _ in Issue.record("no write"); return .empty }.isEmpty)
    }
}
