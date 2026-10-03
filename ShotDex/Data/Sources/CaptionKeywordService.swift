import Foundation

/// The one path a caption or keyword change takes, from Info and from the
/// bulk sheet alike (FS-02.07 §4, §5): Photos first, in one `performChanges`;
/// then — only once Photos says it went through — the index dates follow
/// the asset (so the next index run does not take the write for an edit and
/// read the file again, AC-12), the mirror reads the written ids back, and
/// the keyword vocabulary is rebuilt. iOS 27 only.
struct CaptionKeywordService: Sendable {
    let writer: any PhotoPropertyWriting
    let reader: any ExtendedMetadataReading
    let mirror: ExtendedMetadataMirrorPass
    let store: PhotoKeywordStore
    let metadataStore: MetadataStore
    /// The library's keywords with counts; `true` recounts them first.
    let keywordCatalog: @Sendable (_ recount: Bool) async -> [KeywordCount]

    /// Photos' caption and keywords for the ids, read live.
    func read(ids: [String]) -> [String: CaptionKeywords] {
        reader.read(ids: ids)
    }

    /// Writes the changes; throws when Photos refused the whole block. The
    /// result names the ids Photos would not let the app change.
    @discardableResult
    func apply(_ changes: [String: CaptionKeywordChange]) async throws -> PropertyWriteResult {
        let wanted = changes.filter { !$0.value.isEmpty }
        guard !wanted.isEmpty else { return .empty }
        let result = try await writer.applyCaptionKeywords(wanted)
        try? metadataStore.recordPropertyWrite(result)
        await mirror.refresh(ids: wanted.keys.filter { !result.refused.contains($0) })
        _ = await keywordCatalog(true)
        return result
    }

    /// Info's live read is the safety net for a change Photos' history did
    /// not report (FS-02.07 §4): a mirror out of step with it is rewritten.
    /// Returns whether it was.
    @discardableResult
    func repairMirror(assetId: String, live: CaptionKeywords) async -> Bool {
        let stored = (try? store.value(assetId: assetId)) ?? .empty
        guard stored.caption != live.caption || Set(stored.keywords) != Set(live.keywords) else { return false }
        await mirror.record([assetId: live])
        _ = await keywordCatalog(true)
        return true
    }
}
