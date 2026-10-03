import Foundation
import Observation

/// The selection's *Caption & Keywords…* sheet (FS-02.07 §5, iOS 27). Reads
/// the selected photos' caption and keywords live from Photos, collects what
/// to add, what to take off and the caption, and applies it all as **one**
/// write. Undo writes back exactly what that write changed — also one write.
@MainActor
@Observable
final class CaptionKeywordSheetModel {
    enum Outcome: Equatable {
        /// Written; the banner text, and how many photos Photos refused.
        case written(banner: String, refused: Int)
        /// Nothing to write.
        case nothing
        /// Photos refused every photo — nothing was written.
        case allRefused
        /// The write failed; Photos made no change.
        case failed
    }

    let ids: [String]
    @ObservationIgnored private let service: CaptionKeywordService
    /// A write that runs longer than this shows *Updating N photos…*.
    @ObservationIgnored let modalDelay: Duration

    private(set) var plan: CaptionKeywordBatchPlan
    private(set) var catalog: [KeywordCount] = []
    private(set) var isLoaded = false
    private(set) var isApplying = false
    /// The write has run longer than `modalDelay`.
    private(set) var showsProgress = false
    var keywordText = ""
    /// The caption field. `captionIsEdited` is what makes Apply write it.
    var captionText = "" {
        didSet { if captionText != oldValue, isLoaded { captionIsEdited = true } }
    }
    private(set) var captionIsEdited = false
    private(set) var clearsCaptions = false

    /// What the last Apply wrote, kept for Undo.
    @ObservationIgnored private(set) var lastWrite: (changes: [String: CaptionKeywordChange], before: [String: CaptionKeywords])?

    init(ids: [String], service: CaptionKeywordService, modalDelay: Duration = .seconds(1)) {
        self.ids = ids
        self.service = service
        self.modalDelay = modalDelay
        self.plan = CaptionKeywordBatchPlan(current: [:])
    }

    var additions: [String] { plan.additions }
    var rows: [CaptionKeywordBatchPlan.Row] { plan.rows }
    var photoCount: Int { ids.count }

    /// The field shows *Multiple Captions* as its placeholder when the photos
    /// disagree and the user has not typed (AC-7).
    var hasMultipleCaptions: Bool { plan.sharedCaption == nil }

    var suggestions: [KeywordCount] {
        let fragment = keywordText.split(separator: ",").last.map(String.init) ?? ""
        return KeywordInput.suggestions(for: fragment, in: catalog, excluding: plan.additions)
    }

    var canApply: Bool {
        isLoaded && !isApplying && !currentPlan.changes.isEmpty
    }

    func load() async {
        let live = service.read(ids: ids)
        // An id Photos no longer returns is not part of the write.
        plan = CaptionKeywordBatchPlan(current: live)
        captionText = (plan.sharedCaption ?? nil) ?? ""
        catalog = await service.keywordCatalog(false)
        isLoaded = true
    }

    /// Return in the field: what was typed joins the pending additions, in
    /// the library's spelling when it has one.
    func commitKeywordText() {
        let typed = KeywordInput.keywords(from: keywordText, existing: KeywordInput.spellings(catalog))
        keywordText = ""
        add(typed)
    }

    func add(_ suggestion: KeywordCount) {
        keywordText = ""
        add([suggestion.keyword])
    }

    private func add(_ keywords: [String]) {
        let present = Set(plan.additions.map(KeywordInput.caseKey))
        plan.additions += keywords.filter { !present.contains(KeywordInput.caseKey($0)) }
    }

    func removeAddition(_ keyword: String) {
        plan.additions.removeAll { $0 == keyword }
    }

    func isRemoving(_ row: CaptionKeywordBatchPlan.Row) -> Bool {
        plan.removals.contains(row.caseKey)
    }

    /// The ⊖ on a row of *On These Photos*: keep ↔ take off all 30.
    func toggleRemoval(_ row: CaptionKeywordBatchPlan.Row) {
        if plan.removals.contains(row.caseKey) {
            plan.removals.remove(row.caseKey)
        } else {
            plan.removals.insert(row.caseKey)
        }
    }

    func clearCaptions() {
        clearsCaptions = true
        captionIsEdited = true
        captionText = ""
    }

    /// The plan Apply writes: the caption only when the field was touched.
    var currentPlan: CaptionKeywordBatchPlan {
        var plan = self.plan
        if !captionIsEdited {
            plan.caption = .untouched
        } else if clearsCaptions && captionText.isEmpty {
            plan.caption = .clear
        } else {
            plan.caption = .set(captionText)
        }
        return plan
    }

    /// Apply: one write for every photo. Typed-but-not-returned keyword text
    /// counts as added.
    func apply() async -> Outcome {
        if !keywordText.trimmingCharacters(in: .whitespaces).isEmpty { commitKeywordText() }
        let plan = currentPlan
        let changes = plan.changes
        guard !changes.isEmpty else { return .nothing }
        isApplying = true
        defer {
            isApplying = false
            showsProgress = false
        }
        let delay = modalDelay
        let progress = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.showsProgress = true
        }
        defer { progress.cancel() }
        do {
            let result = try await service.apply(changes)
            let written = changes.filter { !result.refused.contains($0.key) }
            guard !written.isEmpty else { return .allRefused }
            lastWrite = (written, plan.current)
            let banner = result.refused.isEmpty
                ? plan.bannerText(written: written.count) ?? ""
                : KeywordCopy.refusedBanner(photos: result.refused.count)
            return .written(banner: banner, refused: result.refused.count)
        } catch {
            return .failed
        }
    }

    /// Undo of the last Apply: one write, exactly backwards (AC-5).
    func undo() async throws {
        guard let lastWrite else { return }
        self.lastWrite = nil
        let inverse = CaptionKeywordBatchPlan.inverse(of: lastWrite.changes, before: lastWrite.before)
        try await service.apply(inverse)
    }
}
