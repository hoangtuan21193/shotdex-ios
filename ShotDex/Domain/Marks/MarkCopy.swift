import Foundation

/// The words of FS-01.12 and FS-01.12b. Every string lives in the `Marks`
/// string table (`Resources/Marks.xcstrings`); counts go through its plural
/// variants. `locale` is injectable for tests.
enum MarkCopy {
    static let table = "Marks"

    /// `★★★★☆` — filled stars then hollow ones to five. Empty for 0, so a
    /// line that joins tokens drops it.
    static func stars(_ rating: Int) -> String {
        let filled = StarRating.clamped(rating)
        guard filled > 0 else { return "" }
        return String(repeating: "★", count: filled) + String(repeating: "☆", count: StarRating.range.upperBound - filled)
    }

    /// `★4` — the grid tile's compact form.
    static func compactStars(_ rating: Int) -> String {
        "★\(StarRating.clamped(rating))"
    }

    static func flagWord(_ flag: PhotoFlag, locale: Locale = .current) -> String {
        switch flag {
        case .pick: String(localized: "Picked", table: table, locale: locale, comment: "A photo's flag: kept in a culling pass")
        case .reject: String(localized: "Rejected", table: table, locale: locale, comment: "A photo's flag: dropped in a culling pass")
        }
    }

    /// The viewer's line-2 segment: `★★★★☆ · Picked`. Nil when the photo has
    /// neither, so the line adds nothing (FS-01.12 §7).
    static func viewerSegment(_ marks: PhotoMarkSummary, locale: Locale = .current) -> String? {
        let parts = [stars(marks.rating), marks.flag.map { flagWord($0, locale: locale) } ?? ""]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `3 stars, Picked` — what VoiceOver adds after a tile's other states.
    static func accessibility(_ marks: PhotoMarkSummary, locale: Locale = .current) -> String? {
        var parts: [String] = []
        if marks.rating > 0 {
            parts.append(String(localized: "\(marks.rating) stars", table: table, locale: locale, comment: "VoiceOver: a photo's star rating (plural)"))
        }
        if let flag = marks.flag { parts.append(flagWord(flag, locale: locale)) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: Menus

    static var rating: String { String(localized: "Rating", table: table, comment: "Menu: the star-rating submenu") }
    static var flag: String { String(localized: "Flag", table: table, comment: "Menu: the Pick/Reject submenu") }
    static var noRating: String { String(localized: "None", table: table, comment: "Rating menu: clear the stars") }
    static var pick: String { String(localized: "Pick", table: table, comment: "Flag menu: keep this photo") }
    static var reject: String { String(localized: "Reject", table: table, comment: "Flag menu: drop this photo") }
    static var clearFlag: String { String(localized: "Clear Flag", table: table, comment: "Flag menu: remove Pick or Reject") }

    /// VoiceOver name of a stars row in the Rating menu, whose title is glyphs.
    static func starsAccessibility(_ rating: Int, locale: Locale = .current) -> String {
        String(localized: "\(rating) stars", table: table, locale: locale, comment: "VoiceOver: a photo's star rating (plural)")
    }

    // MARK: Filters (FS-01.12 §7)

    static var picksFilter: String { String(localized: "Picks", table: table, comment: "Filter menu row and chip: only Picked photos") }
    static var rejectedFilter: String { String(localized: "Rejected", table: table, comment: "A photo's flag: dropped in a culling pass") }
    static var unflaggedFilter: String { String(localized: "Unflagged", table: table, comment: "Filter chip: photos with neither Pick nor Reject") }
    static var unrated: String { String(localized: "Unrated", table: table, comment: "Rating filter: photos with no stars") }
    static var anyRating: String { String(localized: "Any", table: table, comment: "Rating filter: no constraint on stars") }

    static func flagFilterName(_ filter: PhotoFlagFilter) -> String {
        switch filter {
        case .picks: picksFilter
        case .rejected: rejectedFilter
        case .unflagged: unflaggedFilter
        }
    }

    /// Rating ▸ rows: `★ & Up` … `★★★★★`, `Unrated`.
    static func ratingMenuRow(_ filter: RatingFilter) -> String {
        switch filter {
        case .atLeast(let stars):
            let glyphs = String(repeating: "★", count: StarRating.clamped(stars))
            return stars >= StarRating.range.upperBound
                ? glyphs
                : String(localized: "\(glyphs) & Up", table: table, comment: "Rating filter row, e.g. ★★★ & Up")
        case .unrated:
            return unrated
        }
    }

    /// The chip on the conditions bar: `★ ≥ 3`, `Unrated`.
    static func ratingChip(_ filter: RatingFilter) -> String {
        switch filter {
        case .atLeast(let stars): "★ ≥ \(StarRating.clamped(stars))"
        case .unrated: unrated
        }
    }

    static func ratingChipAccessibility(_ filter: RatingFilter) -> String {
        switch filter {
        case .atLeast(let stars):
            String(localized: "Remove rating filter, \(stars) stars and up", table: table, comment: "VoiceOver: remove the rating chip")
        case .unrated:
            String(localized: "Remove rating filter, unrated", table: table, comment: "VoiceOver: remove the rating chip")
        }
    }

    static func flagChipAccessibility(_ filter: PhotoFlagFilter) -> String {
        String(localized: "Remove flag filter \(flagFilterName(filter))", table: table, comment: "VoiceOver: remove a Picks/Rejected/Unflagged chip")
    }

    // MARK: Errors (NF-04)

    static var ratingWriteFailed: String {
        String(localized: "Couldn't save rating.", table: table, comment: "Banner: writing a star rating to Photos failed")
    }
    static var tryAgain: String {
        String(localized: "Try Again", table: table, comment: "Banner action: repeat the failed write")
    }
}
