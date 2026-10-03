import Foundation
import Testing
@testable import ShotDex

/// FS-02.07 §4 — Info's caption and keywords: read live, written at once,
/// mirrored only after Photos said yes.
@MainActor
struct InfoCaptionKeywordModelTests {

    /// AC-1: `Sunrise at Ba Na`, Done — Photos holds the string; the mirror
    /// changes only once the write has finished; the index date follows the
    /// asset so the next index run does not read the file again.
    @Test func writesThenMirrors() async throws {
        let harness = try CaptionKeywordHarness(["A": .empty])
        let model = InfoCaptionKeywordModel(assetId: "A", service: harness.service)
        await model.load()

        model.captionText = "Sunrise at Ba Na"
        harness.writer.hold()
        let commit = Task { await model.commitCaption() }
        while !harness.writer.isHolding { await Task.yield() }
        #expect(try harness.store.value(assetId: "A").caption == nil)
        harness.writer.release()
        await commit.value

        #expect(harness.library.read(ids: ["A"])["A"]?.caption == "Sunrise at Ba Na")
        #expect(try harness.store.value(assetId: "A").caption == "Sunrise at Ba Na")
        #expect(harness.writer.blocks.count == 1)
        #expect(try harness.modificationDate("A") == harness.writer.modificationDate + 1)

        // Closed and opened again: the field reads it back from Photos.
        let reopened = InfoCaptionKeywordModel(assetId: "A", service: harness.service)
        await reopened.load()
        #expect(reopened.captionText == "Sunrise at Ba Na")
    }

    /// Leaving the field without a change writes nothing.
    @Test func unchangedCaptionWritesNothing() async throws {
        let harness = try CaptionKeywordHarness(["A": CaptionKeywords(caption: "same")])
        let model = InfoCaptionKeywordModel(assetId: "A", service: harness.service)
        await model.load()
        await model.commitCaption()
        #expect(harness.writer.blocks.isEmpty)
    }

    /// The live read is the safety net: a mirror out of step with Photos is
    /// rewritten when Info opens.
    @Test func liveReadRepairsMirror() async throws {
        let harness = try CaptionKeywordHarness(["A": CaptionKeywords(caption: "new", keywords: ["Sunset"])])
        try harness.store.replace(["A": CaptionKeywords(caption: "old", keywords: ["stale"])])
        let model = InfoCaptionKeywordModel(assetId: "A", service: harness.service)
        await model.load()
        #expect(model.captionText == "new")
        #expect(model.keywords == ["Sunset"])
        #expect(try harness.store.value(assetId: "A") == CaptionKeywords(caption: "new", keywords: ["Sunset"]))
        #expect(harness.writer.blocks.isEmpty)
    }

    /// A failed write leaves Photos and the mirror as they were and offers
    /// Try Again, which writes the same change.
    @Test func failureOffersRetry() async throws {
        let harness = try CaptionKeywordHarness(["A": .empty])
        let model = InfoCaptionKeywordModel(assetId: "A", service: harness.service)
        await model.load()
        harness.writer.failure = CocoaError(.fileWriteUnknown)
        model.captionText = "x"
        await model.commitCaption()
        #expect(model.failedChange == CaptionKeywordChange(caption: .set("x")))
        #expect(try harness.store.value(assetId: "A") == .empty)
        harness.writer.failure = nil
        await model.retry()
        #expect(model.failedChange == nil)
        #expect(harness.library.read(ids: ["A"])["A"]?.caption == "x")
    }

    /// The caption field stops at Photos' 2,000-character ceiling (§10 q5).
    @Test func captionStopsAtPhotosCeiling() {
        #expect(InfoCaptionKeywordModel.limitedCaption(String(repeating: "a", count: 2_500)).utf16.count == 2_000)
        #expect(InfoCaptionKeywordModel.limitedCaption("short") == "short")
    }
}
