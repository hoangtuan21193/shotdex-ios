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
}
