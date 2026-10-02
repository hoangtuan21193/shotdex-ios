import Foundation
import Testing
@testable import ShotDex

/// FS-01.12b AC-4 — the counts at the end of the pass.
@MainActor
struct CullSummaryTests {

    /// 240 photos: 52 Picked, 119 Rejected, the last one unflagged. `X` on
    /// it → the pass ends on the summary: 240 · 52 · 120 · 68.
    @Test func counts() async throws {
        let marks = PhotoMarks(store: PhotoMarksStore(database: try AppDatabase.makeEmpty()))
        let items = CullSessionTests.items()
        var session = CullSession.start(items: items, flagged: { _ in false }, startId: "p239")
        await marks.setFlag(.pick, ids: (0..<52).map { String(format: "p%03d", $0) })
        await marks.setFlag(.reject, ids: (52..<171).map { String(format: "p%03d", $0) })

        let reject = await marks.setFlag(.reject, ids: [session.currentId!])
        #expect(session.didSetFlag(reject) == .summary)

        let summary = CullSummary(ids: session.ids, flag: marks.flag(for:))
        #expect(summary.total == 240 && summary.picks == 52 && summary.rejected == 120 && summary.unflagged == 68)
        let en = Locale(identifier: "en_US")
        #expect(MarkCopy.cullSummary(summary, locale: en) == "240 photos · 52 picks · 120 rejected · 68 unflagged")
        #expect(MarkCopy.deleteRejected(120, locale: en) == "Delete 120 Rejected…")
    }

    @Test func reviewUnflaggedSubset() {
        let flags: [String: PhotoFlag] = ["a": .pick, "c": .reject]
        let ids = ["a", "b", "c", "d"]
        #expect(CullSummary.unflaggedIds(ids, flag: { flags[$0] }) == ["b", "d"])
        #expect(CullSummary.rejectedIds(ids, flag: { flags[$0] }) == ["c"])
    }
}
