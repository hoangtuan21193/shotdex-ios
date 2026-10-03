import Foundation
import Testing
@testable import ShotDex

/// FS-02.07 §5 — the selection's *Caption & Keywords…* sheet against a fake
/// Photos: what Apply writes, in how many blocks, and what the banner says.
@MainActor
struct CaptionKeywordSheetModelTests {

    static func thirty(hoiAn: Int = 12) -> [String: CaptionKeywords] {
        CaptionKeywordBatchPlanTests.thirty(hoiAn: hoiAn)
    }

    static func ids(_ photos: [String: CaptionKeywords]) -> [String] {
        photos.keys.sorted()
    }

    /// AC-4: 30 selected, 12 already with `Hoi An`; add `Hoi An` and
    /// `2026 trip`, Apply — one write, every photo has both once, the banner
    /// says *Added 2 keywords to 30 photos*.
    @Test func applyIsOneWrite() async throws {
        let photos = Self.thirty()
        let harness = try CaptionKeywordHarness(photos)
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service)
        await model.load()
        model.keywordText = "Hoi An, 2026 trip"
        model.commitKeywordText()
        #expect(model.additions == ["Hoi An", "2026 trip"])

        let outcome = await model.apply()

        #expect(harness.writer.blocks.count == 1)
        #expect(harness.writer.blocks.first?.count == 30)
        let after = harness.library.read(ids: Self.ids(photos))
        #expect(after.count == 30)
        for value in after.values {
            #expect(value.keywords.filter { $0 == "Hoi An" }.count == 1)
            #expect(value.keywords.contains("2026 trip"))
        }
        if case .written(let banner, let refused) = outcome {
            #expect(banner == KeywordCopy.addedBanner(keywords: 2, photos: 30))
            #expect(refused == 0)
        } else {
            Issue.record("expected a write, got \(outcome)")
        }
        // The mirror followed Photos.
        #expect(try harness.store.keywordCounts().first { $0.keyword == "Hoi An" }?.count == 30)
    }

    /// A write still running after the modal delay (1 s in the app)
    /// raises *Updating N photos…*; it goes when the write ends.
    @Test func longWriteShowsProgress() async throws {
        let photos = Self.thirty()
        let harness = try CaptionKeywordHarness(photos)
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service, modalDelay: .milliseconds(20))
        await model.load()
        model.keywordText = "x"
        model.commitKeywordText()
        harness.writer.hold()
        let apply = Task { await model.apply() }
        while !harness.writer.isHolding { await Task.yield() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.showsProgress)
        #expect(KeywordCopy.updating(5_000, locale: Locale(identifier: "en")) == "Updating 5,000 photos…")
        harness.writer.release()
        _ = await apply.value
        #expect(!model.showsProgress)
    }

    /// Cancel before Apply writes nothing; an unchanged sheet has nothing
    /// to apply.
    @Test func nothingToApply() async throws {
        let photos = Self.thirty()
        let harness = try CaptionKeywordHarness(photos)
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service)
        await model.load()
        #expect(!model.canApply)
        #expect(await model.apply() == .nothing)
        #expect(harness.writer.blocks.isEmpty)
    }

    /// The ⋯ row: Library, album and smart album offer it, On This Day does
    /// not, and below iOS 27 nobody does (AC-14).
    @Test func menuRowHiddenBelow27() {
        #expect(CaptionKeywordsSelectionRow.isOffered(screenOffers: true, extendedMetadata: true))
        #expect(!CaptionKeywordsSelectionRow.isOffered(screenOffers: true, extendedMetadata: false))
        #expect(!CaptionKeywordsSelectionRow.isOffered(screenOffers: false, extendedMetadata: true))
        #expect(PhotoCommand.captionKeywords.systemImage == "tag")
        let menu = PhotoCommand.albumSelectionMenu
        #expect(menu.firstIndex(of: .captionKeywords) == menu.firstIndex(of: .addToCollection).map { $0 + 1 })
    }

    /// Measured 0.9 ms a photo (§10 q3): one block up to 10,000 photos,
    /// blocks of 1,000 above.
    @Test func blocksAboveTenThousand() {
        #expect(CaptionKeywordService.blocks((0..<10_000).map(String.init)).count == 1)
        let blocks = CaptionKeywordService.blocks((0..<12_345).map(String.init))
        #expect(blocks.count == 13)
        #expect(blocks.allSatisfy { $0.count <= 1_000 })
    }

    /// AC-5: Undo right after AC-4 — one more write; `Hoi An` comes off the
    /// 18 that did not have it and stays on the 12 that did; `2026 trip`
    /// comes off all 30.
    @Test func undoWritesBackOnlyChanges() async throws {
        let photos = Self.thirty()
        let harness = try CaptionKeywordHarness(photos)
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service)
        await model.load()
        model.keywordText = "Hoi An, 2026 trip"
        model.commitKeywordText()
        _ = await model.apply()

        try await model.undo()

        #expect(harness.writer.blocks.count == 2)
        #expect(harness.writer.blocks.last?.count == 30)
        let after = harness.library.read(ids: Self.ids(photos))
        #expect(after.values.filter { $0.keywords.contains("Hoi An") }.count == 12)
        #expect(after.values.filter { $0.keywords.contains("2026 trip") }.isEmpty)
        #expect(after == photos)
        #expect(try harness.store.keywordCounts().first { $0.keyword == "Hoi An" }?.count == 12)
    }
}
