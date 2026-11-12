import CoreGraphics
import Testing
@testable import ShotDex

/// How many Recents cards one row shows (DUO_LOOP 3c): three on a phone,
/// more at about 150pt each where the row is wider.
struct SearchRecentsCardCountTests {
    @Test func phoneKeepsThree() {
        // 402pt iPhone minus 20pt margins each side.
        #expect(SearchRecentsModel.cardCount(width: 362, spacing: 12) == 3)
    }

    @Test func unmeasuredRowShowsThree() {
        #expect(SearchRecentsModel.cardCount(width: 0, spacing: 12) == 3)
    }

    @Test func duoInnerShowsFive() {
        // 951pt inner display, 84pt rail, 20pt margins.
        #expect(SearchRecentsModel.cardCount(width: 827, spacing: 12) == 5)
    }

    @Test func largeIPadStopsAtTheLoadedCount() {
        #expect(SearchRecentsModel.cardCount(width: 1336, spacing: 12) == SearchRecentsModel.maximumCards)
        #expect(SearchRecentsModel.cardCount(width: 4000, spacing: 12) == SearchRecentsModel.maximumCards)
    }

    @Test func cardsStayNearTheirPreferredWidth() {
        for width in stride(from: CGFloat(500), through: 1300, by: 50) {
            let count = SearchRecentsModel.cardCount(width: width, spacing: 12)
            let card = (width - CGFloat(count - 1) * 12) / CGFloat(count)
            #expect(card >= SearchRecentsModel.preferredCardWidth, "\(width)pt row")
            #expect(card < SearchRecentsModel.preferredCardWidth * 2, "\(width)pt row")
        }
    }
}
