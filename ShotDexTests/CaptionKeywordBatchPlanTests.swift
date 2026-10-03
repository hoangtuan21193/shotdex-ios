import Foundation
import Testing
@testable import ShotDex

/// FS-02.07 §5 — the bulk sheet's Apply and Undo as data.
struct CaptionKeywordBatchPlanTests {

    /// 30 photos, the first 12 already carrying `Hoi An`.
    static func thirty(hoiAn: Int = 12) -> [String: CaptionKeywords] {
        Dictionary(uniqueKeysWithValues: (0..<30).map { index in
            ("p\(index)", CaptionKeywords(caption: nil, keywords: index < hoiAn ? ["Hoi An"] : []))
        })
    }

    /// AC-4: adding `Hoi An` and `2026 trip` to 30 photos — every photo ends
    /// with both, none with `Hoi An` twice; the 12 that had it get only the trip.
    @Test func addTwoToThirty() {
        let plan = CaptionKeywordBatchPlan(current: Self.thirty(), additions: ["Hoi An", "2026 trip"])
        let changes = plan.changes
        #expect(changes.count == 30)
        #expect(changes.values.filter { $0.add == ["Hoi An", "2026 trip"] }.count == 18)
        #expect(changes.values.filter { $0.add == ["2026 trip"] }.count == 12)
        for (id, change) in changes {
            let after = change.applied(to: plan.current[id]!)
            #expect(after.keywords.filter { $0 == "Hoi An" }.count == 1)
            #expect(after.keywords.contains("2026 trip"))
            #expect(change.caption == .untouched)
        }
        #expect(plan.bannerText(written: 30, locale: Locale(identifier: "en")) == "Added 2 keywords to 30 photos")
    }

    /// Typed in another case than the photo's own: no second spelling.
    @Test func addSkipsOtherCase() {
        let plan = CaptionKeywordBatchPlan(
            current: ["a": CaptionKeywords(keywords: ["sunset"])], additions: ["Sunset"]
        )
        #expect(plan.changes.isEmpty)
    }

    /// AC-5: Undo takes `Hoi An` off exactly the 18 that did not have it and
    /// `2026 trip` off all 30.
    @Test func inverseRemovesOnlyAdded() {
        let plan = CaptionKeywordBatchPlan(current: Self.thirty(), additions: ["Hoi An", "2026 trip"])
        let undo = plan.inverse
        #expect(undo.count == 30)
        #expect(undo.values.filter { $0.remove.contains("Hoi An") }.count == 18)
        #expect(undo.values.filter { $0.remove.contains("2026 trip") }.count == 30)
        #expect(undo.values.allSatisfy { $0.add.isEmpty && $0.caption == .untouched })
        for (id, change) in plan.changes {
            let back = undo[id]!.applied(to: change.applied(to: plan.current[id]!))
            #expect(back == plan.current[id]!)
        }
    }

    @Test func inverseRestoresCaptions() {
        let current: [String: CaptionKeywords] = [
            "a": CaptionKeywords(caption: "one"),
            "b": CaptionKeywords(caption: "two"),
            "c": CaptionKeywords(caption: nil),
        ]
        let plan = CaptionKeywordBatchPlan(current: current, caption: .set("same"))
        let undo = plan.inverse
        #expect(undo["a"]?.caption == .set("one"))
        #expect(undo["b"]?.caption == .set("two"))
        #expect(undo["c"]?.caption == .clear)
        #expect(plan.bannerText(written: 3, locale: Locale(identifier: "en")) == "Updated 3 photos")
    }

    /// AC-6: `Sunset` on 5 and `sunset` on 2 is one row `Sunset · 7`; taking
    /// it off removes both spellings and nothing else.
    @Test func removeFoldsCase() {
        var current = Self.thirty(hoiAn: 0)
        for index in 0..<5 { current["p\(index)"] = CaptionKeywords(keywords: ["Sunset", "beach"]) }
        for index in 5..<7 { current["p\(index)"] = CaptionKeywords(keywords: ["sunset"]) }
        var plan = CaptionKeywordBatchPlan(current: current)
        let row = plan.rows.first { $0.caseKey == "sunset" }
        #expect(row == CaptionKeywordBatchPlan.Row(keyword: "Sunset", caseKey: "sunset", count: 7))
        #expect(KeywordCopy.share(row?.count ?? 0, of: current.count, locale: Locale(identifier: "en")) == "7 of 30")

        plan.removals = ["sunset"]
        let after = plan.changes.reduce(into: current) { result, entry in
            result[entry.key] = entry.value.applied(to: current[entry.key]!)
        }
        #expect(after.values.filter { $0.keywords.contains { KeywordInput.caseKey($0) == "sunset" } }.isEmpty)
        #expect(after.values.filter { $0.keywords.contains("beach") }.count == 5)
        #expect(plan.changes.count == 7)
    }

    /// AC-7: three different captions, caption field untouched, a keyword
    /// added — every caption stays byte for byte, and none is written.
    @Test func untouchedCaptionWritesNothing() {
        var current = Self.thirty(hoiAn: 0)
        let captions = ["Sunrise at Ba Na", "Đà Lạt, sương sớm", "  spaced  "]
        for index in 0..<30 { current["p\(index)"]?.caption = captions[index % 3] }
        let plan = CaptionKeywordBatchPlan(current: current, additions: ["x"])
        #expect(plan.sharedCaption == nil)
        #expect(plan.changes.values.allSatisfy { $0.caption == .untouched })
        for (id, change) in plan.changes {
            #expect(change.applied(to: current[id]!).caption == current[id]!.caption)
        }
    }

    @Test func sharedCaptionShowsWhenAllAgree() {
        let same = CaptionKeywordBatchPlan(current: ["a": .init(caption: "x"), "b": .init(caption: "x")])
        #expect(same.sharedCaption == .some("x"))
        let none = CaptionKeywordBatchPlan(current: ["a": .empty, "b": .empty])
        #expect(none.sharedCaption == .some(nil))
    }

    /// Clear Captions writes only to photos that have one; a blank set is a clear.
    @Test func clearCaptionsTouchesOnlyCaptioned() {
        let current: [String: CaptionKeywords] = ["a": .init(caption: "one"), "b": .empty]
        let clear = CaptionKeywordBatchPlan(current: current, caption: .clear)
        #expect(clear.changes == ["a": CaptionKeywordChange(caption: .clear)])
        let blank = CaptionKeywordBatchPlan(current: current, caption: .set("   "))
        #expect(blank.changes == ["a": CaptionKeywordChange(caption: .clear)])
    }
}
