import CoreGraphics
import Testing
@testable import ShotDex

/// How many card columns the compare screen takes, and how cards are dealt
/// into them. The interesting cases are the ones that are awkward to reach by
/// hand: the Duo's cover display, an iPad in portrait, and a comparison with
/// fewer photos than the screen has room for.
struct CompareLayoutTests {

    private let spacing: CGFloat = 14

    @Test func aPhoneIsOneColumn() {
        // iPhone 17: 402pt wide, 12pt padding each side.
        #expect(CompareLayout.columns(count: 6, width: 378, spacing: spacing) == 1)
    }

    /// The Duo's cover display is 466pt with an 84pt rail — narrower than two
    /// readable cards, so it stays a single column like a phone.
    @Test func theDuoCoverIsOneColumn() {
        #expect(CompareLayout.columns(count: 6, width: 466 - 84 - 24, spacing: spacing) == 1)
    }

    @Test func anIPadInPortraitIsTwoColumnsAndInLandscapeThree() {
        // iPad Pro 11": 834pt portrait, 1194pt landscape.
        #expect(CompareLayout.columns(count: 6, width: 834 - 24, spacing: spacing) == 2)
        #expect(CompareLayout.columns(count: 6, width: 1194 - 24, spacing: spacing) == 3)
    }

    /// Three columns is the ceiling however wide the display gets: a fourth
    /// card is one too small to tell two exposures apart.
    @Test func threeColumnsIsTheCeiling() {
        #expect(CompareLayout.columns(count: 12, width: 4000, spacing: spacing) == 3)
    }

    /// Two photos on a 13" iPad are two columns, not three with a hole in it.
    @Test func columnsNeverExceedThePhotoCount() {
        #expect(CompareLayout.columns(count: 2, width: 1366, spacing: spacing) == 2)
        #expect(CompareLayout.columns(count: 1, width: 1366, spacing: spacing) == 1)
    }

    @Test func aCanvasWithNoWidthStillAsksForOneColumn() {
        #expect(CompareLayout.columns(count: 4, width: 0, spacing: spacing) == 1)
        #expect(CompareLayout.columns(count: 0, width: 1000, spacing: spacing) == 1)
    }

    @Test func oneColumnKeepsEveryCardInOrder() {
        let buckets = CompareLayout.distribute(aspectRatios: [1.5, 0.66, 1], columns: 1)
        #expect(buckets == [[0, 1, 2]])
    }

    /// Landscape frames are short and portrait ones are tall, so dealing them
    /// out round-robin would leave one column running far past the other. Each
    /// card goes to whichever column is shortest so far.
    @Test func tallCardsAreBalancedAgainstShortOnes() {
        // One portrait (tall) then four landscape (short).
        let buckets = CompareLayout.distribute(
            aspectRatios: [0.5, 2, 2, 2, 2],
            columns: 2
        )
        #expect(buckets.count == 2)
        #expect(buckets[0].first == 0)
        // The tall frame is 2 units; each short one is 0.5, so the other column
        // takes four of them before the first column is asked for a second.
        #expect(buckets[1].count == 4)
        #expect(buckets.flatMap { $0 }.sorted() == [0, 1, 2, 3, 4])
    }

    @Test func equalCardsAlternateLeftToRight() {
        let buckets = CompareLayout.distribute(aspectRatios: [1, 1, 1, 1], columns: 2)
        #expect(buckets == [[0, 2], [1, 3]])
    }

    /// A missing asset reports a zero ratio; it must not divide the running
    /// height by zero or swallow every later card into one column.
    @Test func aMissingAssetCountsAsSquare() {
        let buckets = CompareLayout.distribute(aspectRatios: [0, 1, 1, 1], columns: 2)
        #expect(buckets.flatMap { $0 }.sorted() == [0, 1, 2, 3])
        #expect(buckets[0].count == 2)
        #expect(buckets[1].count == 2)
    }

    @Test func noPhotosIsNoCards() {
        #expect(CompareLayout.distribute(aspectRatios: [], columns: 3) == [[], [], []])
    }
}
