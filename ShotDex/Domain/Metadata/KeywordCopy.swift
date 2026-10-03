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

    /// `30 Photos` under the sheet's title.
    static func photoCount(_ photos: Int, locale: Locale = .current) -> String {
        String(localized: "\(photos) Photos", table: table, locale: locale, comment: "Caption & Keywords sheet subtitle: number of selected photos (plural, title case)")
    }
}
