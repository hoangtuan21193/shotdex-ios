import Foundation
import Testing
@testable import ShotDex

/// FS-01.12b — the culling pass's order, start and layout.
struct CullSessionTests {

    /// 240 photos, shuffled, one a minute; ids carry their capture order.
    static func items(_ count: Int = 240) -> [CullSession.Item] {
        (0..<count).map { CullSession.Item(id: String(format: "p%03d", $0), captureDate: Date(timeIntervalSince1970: 1_000 + Double($0) * 60)) }
            .shuffled()
    }

    /// b-AC-3: the 36 earliest are flagged → the pass opens on the 37th by
    /// capture date, "37 / 240".
    @Test func startsAtFirstUnflaggedByCaptureDate() {
        let flagged = Set((0..<36).map { String(format: "p%03d", $0) })
        let session = CullSession.start(items: Self.items(), flagged: flagged.contains)

        #expect(session.ids.first == "p000" && session.ids.last == "p239")
        #expect(session.currentId == "p036")
        #expect(session.counter == "37 / 240")
    }

    @Test func everyPhotoFlaggedOpensAtTheFirst() {
        let session = CullSession.start(items: Self.items(5), flagged: { _ in true })
        #expect(session.index == 0)
    }

    @Test func cullFromHereOpensOnThatPhoto() {
        let session = CullSession.start(items: Self.items(10), flagged: { _ in false }, startId: "p007")
        #expect(session.counter == "8 / 10")
    }

    /// FS-01.05 §1: no date goes last; ties break by id.
    @Test func nilDatesLast() {
        let date = Date(timeIntervalSince1970: 5)
        let order = CullSession.ordered([
            .init(id: "c", captureDate: nil),
            .init(id: "b", captureDate: date),
            .init(id: "a", captureDate: date),
            .init(id: "d", captureDate: Date(timeIntervalSince1970: 1)),
        ])
        #expect(order == ["d", "a", "b", "c"])
    }

    @Test func layoutPerDevice() {
        #expect(CullLayout.controlRowWidth == 340)
        let phone = CullLayout.forSize(CGSize(width: 402, height: 820))
        #expect(phone.filmstripHeight == 56 && phone.filmstripCell == 44 && !phone.showsEXIFLine)
        let iPad = CullLayout.forSize(CGSize(width: 1376, height: 1008))
        #expect(iPad.filmstripHeight == 72 && iPad.filmstripCell == 60 && iPad.showsEXIFLine)
        // The Duo's inner screen is wide but 669pt short: the phone strip.
        #expect(!CullLayout.forSize(CGSize(width: 951, height: 653)).showsEXIFLine)
        #expect(!CullLayout.forSize(CGSize(width: 382, height: 666)).showsEXIFLine)
    }

    /// b-AC-1: at 37 of 240, unflagged: `P` → 37 Picked, on to "38 / 240";
    /// `3` → 38 has 3 stars, still on 38; ⌘Z → 38 back to no stars; ⌘Z →
    /// 37 unflagged and the pass back on 37.
    @MainActor
    @Test func pickAdvancesStarStaysUndoReturns() async throws {
        let marks = PhotoMarks(store: PhotoMarksStore(database: try AppDatabase.makeEmpty()))
        var session = CullSession.start(items: Self.items(), flagged: { _ in false }, startId: "p036")
        #expect(session.counter == "37 / 240")

        let pick = await marks.setFlag(.pick, ids: [session.currentId!])
        #expect(session.didSetFlag(pick) == .next)
        #expect(marks.flag(for: "p036") == .pick)
        #expect(session.counter == "38 / 240")

        let three = await marks.setRating(3, ids: [session.currentId!])
        #expect(session.didSetRating(three) == .stay)
        #expect(marks.rating(for: "p037") == 3)
        #expect(session.counter == "38 / 240")

        await marks.undo(try #require(session.undo()))
        #expect(marks.rating(for: "p037") == 0)
        #expect(session.counter == "38 / 240")

        await marks.undo(try #require(session.undo()))
        #expect(marks.flag(for: "p036") == nil)
        #expect(session.counter == "37 / 240")
        #expect(!session.canUndo)
    }

    @Test func flagOnTheLastPhotoOpensTheSummary() {
        var session = CullSession.start(items: Self.items(3), flagged: { _ in false }, startId: "p002")
        #expect(session.didSetFlag(MarkChange(kind: .flag(previous: ["p002": nil]))) == .summary)
        #expect(session.counter == "3 / 3")
    }

    @Test func keysCoverMarksAndZoomWithoutClashing() {
        let keys = CullKey.characterBindings.map(\.0)
        #expect(Set(keys).count == keys.count)
        #expect(keys.contains("z") && keys.contains("p") && keys.contains("0"))
    }
}
