import Foundation
import Observation

/// Info's caption and keywords for the photo on screen (FS-02.07 §4, iOS 27).
/// Reads them live from Photos each time Info opens — and rewrites the
/// mirror when it was out of step — and writes every change straight away:
/// the caption when the field is left or Done is pressed, a keyword on each
/// add or ×. Each is one write to Photos; the mirror follows only after
/// Photos said it went through.
@MainActor
@Observable
final class InfoCaptionKeywordModel {
    let assetId: String
    @ObservationIgnored private let service: CaptionKeywordService

    /// What Photos holds now.
    private(set) var saved: CaptionKeywords = .empty
    /// The caption field's text.
    var captionText = ""
    /// The Add Keyword field's text.
    var keywordText = ""
    private(set) var catalog: [KeywordCount] = []
    private(set) var isLoaded = false
    private(set) var isWriting = false
    /// Set when a write failed; the view offers Try Again.
    private(set) var failedChange: CaptionKeywordChange?

    var keywords: [String] { saved.keywords }

    /// Photos refuses a caption over 2,000 characters — the whole write fails
    /// (FS-02.07 §10 q5) — so the field stops there. Counted in UTF-16, the
    /// stricter of the two counts the measurement could not tell apart.
    static let captionLimit = 2_000

    static func limitedCaption(_ text: String) -> String {
        guard text.utf16.count > captionLimit else { return text }
        var result = ""
        var units = 0
        for character in text {
            let width = character.utf16.count
            guard units + width <= captionLimit else { break }
            result.append(character)
            units += width
        }
        return result
    }

    /// Up to 8 library keywords for what is typed, most photos first.
    var suggestions: [KeywordCount] {
        let fragment = keywordText.split(separator: ",").last.map(String.init) ?? ""
        return KeywordInput.suggestions(for: fragment, in: catalog, excluding: saved.keywords)
    }

    init(assetId: String, service: CaptionKeywordService, catalog: [KeywordCount] = []) {
        self.assetId = assetId
        self.service = service
        self.catalog = catalog
    }

    /// Reads Photos, and repairs the mirror if it disagrees.
    func load() async {
        let live = service.read(ids: [assetId])[assetId] ?? .empty
        saved = live
        captionText = live.caption ?? ""
        isLoaded = true
        await service.repairMirror(assetId: assetId, live: live)
        catalog = await service.keywordCatalog(false)
    }

    /// The field was left or Done pressed: writes the caption if it changed.
    /// Clearing the text clears the caption (AC-2).
    func commitCaption() async {
        let trimmed = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let change: CaptionKeywordChange.Caption
        if trimmed.isEmpty {
            guard saved.caption != nil else { captionText = ""; return }
            change = .clear
        } else {
            guard captionText != saved.caption else { return }
            change = .set(captionText)
        }
        await write(CaptionKeywordChange(caption: change))
    }

    /// Return in the Add Keyword field: `sunset, beach` adds two, each in the
    /// library's own spelling when it has one (AC-3).
    func commitKeywords() async {
        let typed = KeywordInput.keywords(from: keywordText, existing: KeywordInput.spellings(catalog))
        let present = Set(saved.keywords.map(KeywordInput.caseKey))
        let adding = typed.filter { !present.contains(KeywordInput.caseKey($0)) }
        keywordText = ""
        guard !adding.isEmpty else { return }
        await write(CaptionKeywordChange(add: adding))
    }

    /// A tapped suggestion is added as it is spelled.
    func add(_ suggestion: KeywordCount) async {
        keywordText = ""
        guard !saved.keywords.map(KeywordInput.caseKey).contains(KeywordInput.caseKey(suggestion.keyword)) else { return }
        await write(CaptionKeywordChange(add: [suggestion.keyword]))
    }

    func remove(_ keyword: String) async {
        await write(CaptionKeywordChange(remove: [keyword]))
    }

    func retry() async {
        guard let change = failedChange else { return }
        failedChange = nil
        await write(change)
    }

    func dismissFailure() {
        failedChange = nil
        captionText = saved.caption ?? ""
    }

    private func write(_ change: CaptionKeywordChange) async {
        isWriting = true
        defer { isWriting = false }
        do {
            let result = try await service.apply([assetId: change])
            if result.refused.contains(assetId) {
                failedChange = nil
                captionText = saved.caption ?? ""
                return
            }
            saved = change.applied(to: saved)
            captionText = saved.caption ?? ""
            catalog = await service.keywordCatalog(false)
        } catch {
            failedChange = change
        }
    }
}
