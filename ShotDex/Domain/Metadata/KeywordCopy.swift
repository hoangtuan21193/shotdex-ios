import Foundation

/// The words of FS-02.07 that Swift code composes. Every string lives in the
/// `Keywords` string table (`Resources/Keywords.xcstrings`); counts go through
/// its plural variants. `locale` is injectable for tests.
enum KeywordCopy {
    static let table = "Keywords"

    static func addedBanner(keywords: Int, photos: Int, locale: Locale = .current) -> String {
        if keywords == 1 {
            return String(
                localized: "Added 1 keyword to \(photos) photos", table: table, locale: locale,
                comment: "Banner after Caption & Keywords added one keyword to the selection (plural on photos)"
            )
        }
        return String(
            localized: "Added \(keywords) keywords to \(photos) photos", table: table, locale: locale,
            comment: "Banner after Caption & Keywords added keywords; first number keywords (2 or more), second photos (plural)"
        )
    }

    static func updatedBanner(photos: Int, locale: Locale = .current) -> String {
        String(
            localized: "Updated \(photos) photos", table: table, locale: locale,
            comment: "Banner after Caption & Keywords changed captions or removed keywords (plural)"
        )
    }

    static func refusedBanner(photos: Int, locale: Locale = .current) -> String {
        String(
            localized: "\(photos) photos can't be changed.", table: table, locale: locale,
            comment: "Banner when Photos refused to change some of the selected photos (plural)"
        )
    }

    /// `12 of 30` on a row of *On These Photos*.
    static func share(_ count: Int, of total: Int, locale: Locale = .current) -> String {
        String(localized: "\(count) of \(total)", table: table, locale: locale, comment: "Caption & Keywords: a keyword is on 12 of the 30 selected photos")
    }

    static func updating(_ photos: Int, locale: Locale = .current) -> String {
        String(localized: "Updating \(photos) photos…", table: table, locale: locale, comment: "Modal while a large Caption & Keywords write runs (plural)")
    }

    /// The chip of a Keyword or Caption condition (FS-02.07 §7):
    /// `keyword: Sunset`, `no keywords`, `caption contains "wedding"`.
    static func chip(for rule: SmartAlbumRule, locale: Locale = .current) -> String {
        let value = rule.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (rule.field, rule.op) {
        case (.keyword, .hasKeyword):
            return String(localized: "keyword: \(value)", table: table, locale: locale, comment: "Chip: photos with this keyword")
        case (.keyword, .lacksKeyword):
            return String(localized: "keyword ≠ \(value)", table: table, locale: locale, comment: "Chip: photos without this keyword")
        case (.keyword, .hasAnyKeyword):
            return String(localized: "any keyword", table: table, locale: locale, comment: "Chip: photos with at least one keyword")
        case (.keyword, .hasNoKeywords):
            return String(localized: "no keywords", table: table, locale: locale, comment: "Chip: photos with no keyword")
        case (.caption, .doesNotContain):
            return String(localized: "caption excludes \"\(value)\"", table: table, locale: locale, comment: "Chip: caption does not contain the text")
        default:
            return String(localized: "caption contains \"\(value)\"", table: table, locale: locale, comment: "Chip: caption contains the text")
        }
    }

    static var undo: String {
        String(localized: "Undo", table: table, comment: "Banner action: write back what Caption & Keywords just changed")
    }

    static var undoFailed: String {
        String(localized: "Couldn't undo the change.", table: table, comment: "Banner when undoing a Caption & Keywords write failed")
    }

    /// `30 Photos` under the sheet's title.
    static func photoCount(_ photos: Int, locale: Locale = .current) -> String {
        String(localized: "\(photos) Photos", table: table, locale: locale, comment: "Caption & Keywords sheet subtitle: number of selected photos (plural, title case)")
    }
}
