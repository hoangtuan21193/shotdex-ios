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

    /// AC-6: `Sunset` on 5 and `sunset` on 2 read as one row `Sunset · 7 of
    /// 30`; ⊖ and Apply take every spelling off, nothing else.
    @Test func removalFoldsCase() async throws {
        var photos = Self.thirty(hoiAn: 0)
        for index in 0..<5 { photos[String(format: "p%d", index)] = CaptionKeywords(keywords: ["Sunset", "beach"]) }
        for index in 5..<7 { photos[String(format: "p%d", index)] = CaptionKeywords(keywords: ["sunset"]) }
        let harness = try CaptionKeywordHarness(photos)
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service)
        await model.load()
        let row = try #require(model.rows.first { $0.caseKey == "sunset" })
        #expect(row.keyword == "Sunset" && row.count == 7)
        model.toggleRemoval(row)
        #expect(model.isRemoving(row))
        let outcome = await model.apply()

        let after = harness.library.read(ids: Self.ids(photos))
        #expect(after.values.allSatisfy { !$0.keywords.contains { KeywordInput.caseKey($0) == "sunset" } })
        #expect(after.values.filter { $0.keywords == ["beach"] }.count == 5)
        #expect(harness.writer.blocks.count == 1)
        #expect(outcome == .written(banner: KeywordCopy.updatedBanner(photos: 7), refused: 0))
    }

    /// AC-7: three different captions; the field shows *Multiple Captions*;
    /// a keyword is added without touching it — every caption stays exactly
    /// as it was, and no caption is written.
    @Test func untouchedCaptionKeepsAll() async throws {
        var photos = Self.thirty(hoiAn: 0)
        let captions = ["Sunrise at Ba Na", "Đà Lạt, sương sớm", "  spaced  "]
        for (index, id) in Self.ids(photos).enumerated() { photos[id]?.caption = captions[index % 3] }
        let harness = try CaptionKeywordHarness(photos)
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service)
        await model.load()
        #expect(model.hasMultipleCaptions)
        #expect(model.captionText.isEmpty)
        model.keywordText = "x"
        model.commitKeywordText()
        _ = await model.apply()

        #expect(harness.writer.blocks.first?.values.allSatisfy { $0.caption == .untouched } == true)
        let after = harness.library.read(ids: Self.ids(photos))
        for (id, value) in photos {
            #expect(after[id]?.caption == value.caption)
        }
    }

    /// Clear Captions writes a clear to every captioned photo — one write.
    @Test func clearCaptionsClearsAll() async throws {
        var photos = Self.thirty(hoiAn: 0)
        photos["p1"]?.caption = "a"
        photos["p2"]?.caption = "b"
        let harness = try CaptionKeywordHarness(photos)
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service)
        await model.load()
        model.clearCaptions()
        _ = await model.apply()
        #expect(harness.writer.blocks == [["p1": CaptionKeywordChange(caption: .clear), "p2": CaptionKeywordChange(caption: .clear)]])
        #expect(harness.library.read(ids: ["p1", "p2"]).values.allSatisfy { $0.caption == nil })
    }

    /// AC-12: 50 photos, 20 of them only in iCloud, no network — `trip` goes
    /// to all 50. The write path has no original fetcher to call: it touches
    /// only `PHAssetChangeRequest` properties, never a resource. And because
    /// Photos moves each photo's modification date (§10 q1), the index rows
    /// are re-stamped with the new date in the same step, so the next index
    /// run sees nothing to read — no original download through the back door.
    @Test func neverFetchesOriginals() async throws {
        let photos = Dictionary(uniqueKeysWithValues: (0..<50).map { ("c\($0)", CaptionKeywords.empty) })
        let harness = try CaptionKeywordHarness(photos)
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service)
        await model.load()
        model.keywordText = "trip"
        model.commitKeywordText()
        _ = await model.apply()

        #expect(harness.library.read(ids: Self.ids(photos)).values.filter { $0.keywords == ["trip"] }.count == 50)
        #expect(harness.writer.resourceRequests == 0)
        let metadata = MetadataStore(database: harness.database)
        for id in Self.ids(photos) {
            let state = try metadata.assetState(assetId: id)
            #expect(state?.modificationDate == harness.writer.modificationDate + 1)
            #expect(!IndexPipeline.needsReindex(
                existing: state,
                currentModificationDate: harness.writer.modificationDate + 1,
                allowNetworkRetry: true
            ))
        }
    }

    /// AC-13: 30 selected, Photos refuses 4 (a shared library, simulated) —
    /// the other 26 get `trip`, the 4 stay as they were, and the banner says
    /// *4 photos can't be changed.*
    @Test func partialRefusal() async throws {
        let photos = Self.thirty(hoiAn: 0)
        let harness = try CaptionKeywordHarness(photos)
        let refused = Set(Self.ids(photos).prefix(4))
        harness.writer.refused = refused
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service)
        await model.load()
        model.keywordText = "trip"
        model.commitKeywordText()
        let outcome = await model.apply()

        let after = harness.library.read(ids: Self.ids(photos))
        #expect(after.filter { $0.value.keywords == ["trip"] }.count == 26)
        #expect(refused.allSatisfy { after[$0] == photos[$0] })
        #expect(outcome == .written(banner: KeywordCopy.refusedBanner(photos: 4), refused: 4))
        #expect(KeywordCopy.refusedBanner(photos: 4, locale: Locale(identifier: "en")) == "4 photos can't be changed.")
        #expect(harness.writer.blocks.count == 1)
        // Undo covers only the 26.
        try await model.undo()
        #expect(harness.writer.blocks.last?.count == 26)
    }

    /// Photos refuses every photo: nothing is written, the sheet alerts.
    @Test func allRefusedAlerts() async throws {
        let photos = Self.thirty(hoiAn: 0)
        let harness = try CaptionKeywordHarness(photos)
        harness.writer.refused = Set(photos.keys)
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service)
        await model.load()
        model.keywordText = "trip"
        model.commitKeywordText()
        #expect(await model.apply() == .allRefused)
        #expect(harness.library.read(ids: Self.ids(photos)) == photos)
    }

    /// The write fails: Photos changed nothing, the mirror changed nothing,
    /// the sheet stays open with Try Again — which writes the same plan.
    @Test func failureLeavesMirror() async throws {
        let photos = Self.thirty(hoiAn: 12)
        let harness = try CaptionKeywordHarness(photos)
        try harness.store.replace(photos)
        let before = try harness.store.keywordCounts()
        harness.writer.failure = CocoaError(.fileWriteUnknown)
        let model = CaptionKeywordSheetModel(ids: Self.ids(photos), service: harness.service)
        await model.load()
        model.keywordText = "trip"
        model.commitKeywordText()
        #expect(await model.apply() == .failed)
        #expect(try harness.store.keywordCounts() == before)
        #expect(harness.library.read(ids: Self.ids(photos)) == photos)

        harness.writer.failure = nil
        if case .written = await model.apply() {} else { Issue.record("Try Again did not write") }
        #expect(harness.library.read(ids: Self.ids(photos)).values.allSatisfy { $0.keywords.contains("trip") })
    }
}
