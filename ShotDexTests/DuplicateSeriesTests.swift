import Foundation
import Testing
@testable import ShotDex

/// The `series` mode: runs of frames of one moment, found by capture time as
/// well as likeness. The cases that matter are the ones the other two modes
/// are built to throw away — frames that are deliberately *not* copies of each
/// other — and the ones a time-chained walk gets wrong if it is written
/// carelessly.
struct DuplicateSeriesTests {

    private let base = 1_700_000_000

    private func photo(
        _ id: String,
        bits: UInt64 = 0,
        secondsIn: Int,
        size: Int? = 10_000_000
    ) -> HashedPhoto {
        HashedPhoto(
            assetId: id,
            hash: PerceptualHash(bits: bits),
            width: 6000,
            height: 4000,
            fileSize: size,
            creationDate: base + secondsIn,
            isFavorite: false
        )
    }

    private func groups(_ photos: [HashedPhoto]) -> [DuplicateGroup] {
        DuplicateGrouper.groups(from: photos, strictness: .series)
    }

    @Test func framesShotSecondsApartAreOneSeries() {
        let result = groups([
            photo("a", secondsIn: 0),
            photo("b", secondsIn: 4),
            photo("c", secondsIn: 9),
        ])
        #expect(result.count == 1)
        #expect(result[0].members.map(\.assetId) == ["a", "b", "c"])
    }

    /// The point of the mode: the pose changed, so the frames are not copies.
    /// `similar` is built to reject exactly this, and must keep doing so.
    @Test func aPoseChangeStaysASeriesButIsNotADuplicate() {
        // Each step is 14 bits: past `similarMaxDistance`, inside
        // `seriesMaxDistance`. That band is the mode's whole reason to exist.
        let photos = [
            photo("a", bits: 0x0000_0000_0000_0000, secondsIn: 0),
            photo("b", bits: 0x0000_0000_0000_3FFF, secondsIn: 5),
            photo("c", bits: 0x0000_0000_0FFF_FFFF, secondsIn: 10),
        ]
        for (left, right) in [(photos[0], photos[1]), (photos[1], photos[2])] {
            let distance = (left.hash.bits ^ right.hash.bits).nonzeroBitCount
            #expect(distance > DuplicateStrictness.similarMaxDistance)
            #expect(distance <= DuplicateStrictness.seriesMaxDistance)
        }
        #expect(groups(photos).count == 1)
        #expect(DuplicateGrouper.groups(from: photos, strictness: .similar).isEmpty)
    }

    /// Each step is compared with the frame before it, not with the first one,
    /// so a run may drift a long way from where it started.
    @Test func aSeriesMayDriftFurtherThanOneStepAllows() {
        let first: UInt64 = 0
        let last: UInt64 = 0x0000_0000_00FF_FFFF
        #expect((first ^ last).nonzeroBitCount > DuplicateStrictness.seriesMaxDistance)

        let result = groups([
            photo("a", bits: first, secondsIn: 0),
            photo("b", bits: 0x0000_0000_0000_0FFF, secondsIn: 5),
            photo("c", bits: last, secondsIn: 10),
        ])
        #expect(result.count == 1)
        #expect(result[0].count == 3)
    }

    @Test func aGapLongerThanTheWindowStartsANewSeries() {
        let result = groups([
            photo("a", secondsIn: 0),
            photo("b", secondsIn: 10),
            photo("c", secondsIn: 20),
            // 31s later: a new run, and it is long enough to be one.
            photo("d", secondsIn: 51),
            photo("e", secondsIn: 55),
            photo("f", secondsIn: 60),
        ])
        #expect(result.count == 2)
        #expect(Set(result.map { Set($0.members.map(\.assetId)) })
            == [["a", "b", "c"], ["d", "e", "f"]])
    }

    /// Exactly the window is still the same run; one second past it is not.
    @Test func theGapBoundaryIsInclusive() {
        let gap = DuplicateStrictness.seriesMaxGap
        #expect(groups([
            photo("a", secondsIn: 0),
            photo("b", secondsIn: gap),
            photo("c", secondsIn: gap * 2),
        ]).count == 1)
        #expect(groups([
            photo("a", secondsIn: 0),
            photo("b", secondsIn: gap + 1),
            photo("c", secondsIn: (gap + 1) * 2),
        ]).isEmpty)
    }

    /// Two frames close together happen all day; only a real run is listed.
    @Test func aPairIsNotASeries() {
        #expect(groups([photo("a", secondsIn: 0), photo("b", secondsIn: 3)]).isEmpty)
        #expect(DuplicateStrictness.series.minimumGroupSize == 3)
    }

    /// Same second, unrelated picture: time alone must not chain them.
    @Test func likenessStillHasToHold() {
        let unrelated: UInt64 = 0xAAAA_AAAA_AAAA_AAAA
        #expect((0 ^ unrelated).nonzeroBitCount > DuplicateStrictness.seriesMaxDistance)
        #expect(groups([
            photo("a", bits: 0, secondsIn: 0),
            photo("b", bits: unrelated, secondsIn: 1),
            photo("c", bits: 0, secondsIn: 2),
        ]).isEmpty)
    }

    /// A series is read in the order it was shot — the whole subject is what
    /// changed between one frame and the next. Duplicate modes lead with the
    /// copy worth keeping instead, and that difference must survive.
    @Test func membersAreInCaptureOrderNotBestFirst() {
        let result = groups([
            photo("late", secondsIn: 10, size: 90_000_000),
            photo("early", secondsIn: 0, size: 1_000),
            photo("middle", secondsIn: 5, size: 50_000_000),
        ])
        #expect(result[0].members.map(\.assetId) == ["early", "middle", "late"])
    }

    @Test func aPhotoWithNoCaptureDateIsLeftOut() {
        var undated = photo("x", secondsIn: 5)
        undated.creationDate = nil
        let result = groups([
            photo("a", secondsIn: 0),
            undated,
            photo("b", secondsIn: 4),
            photo("c", secondsIn: 8),
        ])
        #expect(result.count == 1)
        #expect(result[0].members.map(\.assetId) == ["a", "b", "c"])
    }

    @Test func nothingToGroupIsNoSeries() {
        #expect(groups([]).isEmpty)
        #expect(groups([photo("a", secondsIn: 0)]).isEmpty)
    }

    /// Newest run first, the same as the duplicate lists.
    @Test func newestSeriesComesFirst() {
        let result = groups([
            photo("old1", secondsIn: 0),
            photo("old2", secondsIn: 5),
            photo("old3", secondsIn: 10),
            photo("new1", secondsIn: 1000),
            photo("new2", secondsIn: 1005),
            photo("new3", secondsIn: 1010),
        ])
        #expect(result.map(\.id) == ["new1", "old1"])
    }
}
