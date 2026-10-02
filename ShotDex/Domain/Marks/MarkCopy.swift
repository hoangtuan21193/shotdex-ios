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
}
