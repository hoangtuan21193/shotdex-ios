import Foundation

/// What one write does to one asset's caption and keywords — the unit
/// `PhotoPropertyWriting.applyCaptionKeywords` puts into a single
/// `performChanges` (FS-02.07 §5).
struct CaptionKeywordChange: Equatable, Hashable, Sendable {
    enum Caption: Equatable, Hashable, Sendable {
        /// The caption is not written at all.
        case untouched
        case set(String)
        case clear
    }

    var add: [String] = []
    var remove: [String] = []
    var caption: Caption = .untouched

    var isEmpty: Bool { add.isEmpty && remove.isEmpty && caption == .untouched }

    /// The asset's caption and keywords once this change is applied — what
    /// the mirror holds after Photos says the write went through.
    func applied(to value: CaptionKeywords) -> CaptionKeywords {
        let removed = Set(remove)
        var keywords = value.keywords.filter { !removed.contains($0) }
        for keyword in add where !keywords.contains(keyword) { keywords.append(keyword) }
        let caption: String? = switch self.caption {
        case .untouched: value.caption
        case .set(let text): text
        case .clear: nil
        }
        return CaptionKeywords(caption: caption, keywords: keywords)
    }
}

/// The sheet *Caption & Keywords…* turned into writes (FS-02.07 §5). Pure:
/// it sees each asset's caption and keywords as Photos holds them now and
/// what the user asked for, and answers which asset changes how — and how to
/// take exactly that back.
struct CaptionKeywordBatchPlan: Equatable, Sendable {
    /// Each selected asset as Photos holds it now.
    var current: [String: CaptionKeywords]
    /// Keywords to add, already spelled (`KeywordInput.keywords`).
    var additions: [String] = []
    /// `caseKey`s of the keywords to take off — every spelling goes.
    var removals: Set<String> = []
    var caption: CaptionKeywordChange.Caption = .untouched

    /// One line of *On These Photos*: a keyword the selection carries, in
    /// the spelling most of its photos use, and on how many.
    struct Row: Equatable, Hashable, Sendable, Identifiable {
        var keyword: String
        var caseKey: String
        var count: Int
        var id: String { caseKey }
    }

    /// The keywords on the selection, grouped without regard to case:
    /// `Sunset` ×5 + `sunset` ×2 is one row `Sunset · 7` (AC-6). Most
    /// photos first.
    var rows: [Row] {
        var spellings: [String: [String: Int]] = [:]
        var photos: [String: Int] = [:]
        for value in current.values {
            var seen = Set<String>()
            for keyword in value.keywords {
                let key = KeywordInput.caseKey(keyword)
                spellings[key, default: [:]][keyword, default: 0] += 1
                if seen.insert(key).inserted { photos[key, default: 0] += 1 }
            }
        }
        return spellings.map { key, counts in
            let spelling = counts.max {
                $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key
            }!.key
            return Row(keyword: spelling, caseKey: key, count: photos[key] ?? 0)
        }
        .sorted {
            $0.count != $1.count ? $0.count > $1.count
                : $0.keyword.localizedStandardCompare($1.keyword) == .orderedAscending
        }
    }

    /// The one caption every selected photo shares, nil when they differ —
    /// then the field shows *Multiple Captions* (AC-7). Photos without a
    /// caption share the empty one.
    var sharedCaption: String?? {
        let captions = Set(current.values.map(\.caption))
        return captions.count == 1 ? captions.first : nil
    }

    /// Per asset, what actually changes. An asset that already has a keyword
    /// (in any case) does not get it again; an untouched caption writes no
    /// caption at all; an asset with nothing to change is left out.
    var changes: [String: CaptionKeywordChange] {
        var result: [String: CaptionKeywordChange] = [:]
        for (assetId, value) in current {
            let present = Set(value.keywords.map(KeywordInput.caseKey))
            var change = CaptionKeywordChange()
            change.remove = value.keywords.filter { removals.contains(KeywordInput.caseKey($0)) }
            var adding = Set<String>()
            change.add = additions.filter {
                let key = KeywordInput.caseKey($0)
                return !present.contains(key) && !removals.contains(key) && adding.insert(key).inserted
            }
            switch caption {
            case .untouched:
                break
            case .set(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if value.caption != nil { change.caption = .clear }
                } else if value.caption != text {
                    change.caption = .set(text)
                }
            case .clear:
                if value.caption != nil { change.caption = .clear }
            }
            if !change.isEmpty { result[assetId] = change }
        }
        return result
    }

    /// What Undo writes: only what `changes` did, backwards — a keyword comes
    /// off only the photos that did not have it, a removed spelling goes back
    /// where it was, each photo gets its own old caption (AC-5).
    var inverse: [String: CaptionKeywordChange] {
        Self.inverse(of: changes, before: current)
    }

    static func inverse(
        of changes: [String: CaptionKeywordChange], before: [String: CaptionKeywords]
    ) -> [String: CaptionKeywordChange] {
        var result: [String: CaptionKeywordChange] = [:]
        for (assetId, change) in changes {
            var back = CaptionKeywordChange(add: change.remove, remove: change.add)
            if change.caption != .untouched {
                back.caption = before[assetId]?.caption.map { .set($0) } ?? .clear
            }
            result[assetId] = back
        }
        return result
    }

    /// The banner after Apply: *Added 2 keywords to 30 photos* when the sheet
    /// only added, *Updated 30 photos* otherwise; nil when nothing changed.
    func bannerText(written: Int, locale: Locale = .current) -> String? {
        guard written > 0 else { return nil }
        if !additions.isEmpty, removals.isEmpty, changes.values.allSatisfy({ $0.caption == .untouched }) {
            return KeywordCopy.addedBanner(keywords: additions.count, photos: current.count, locale: locale)
        }
        return KeywordCopy.updatedBanner(photos: written, locale: locale)
    }
}
