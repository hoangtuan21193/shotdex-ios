import Foundation

/// The words on a row of Collages or Video Projects (FS-06.01b §5,
/// FS-12.18 §4), composed in one place so they can be tested.
enum CreationCardCopy {
    /// "Edited 5 min. ago · 5 clips" for a draft, "12 clips" for an exported
    /// video project, "4 photos" for a collage. The relative time is the
    /// system's own format.
    static func subtitle(for creation: Creation, now: Date = .now, locale: Locale = .current) -> String {
        let count = creation.sourceAssetIds.count
        switch creation.kind {
        case .collage:
            return String(
                localized: "\(count) photos",
                comment: "How many photos a saved collage or video was made from"
            )
        case .video:
            let clips = String(
                localized: "\(count) clips", table: VideoStudioCopy.table, locale: locale,
                comment: "Video Projects: how many clips a video project has (plural)"
            )
            guard creation.isDraft else { return clips }
            let edited = String(
                localized: "Edited \(relativeTime(of: creation, now: now, locale: locale))",
                table: VideoStudioCopy.table, locale: locale,
                comment: "Video Projects: when a draft was last changed; the argument is a relative time such as '5 min. ago'"
            )
            return String(
                localized: "\(edited) · \(clips)", table: VideoStudioCopy.table, locale: locale,
                comment: "Video Projects: a draft's subtitle — when it was edited, then how many clips"
            )
        }
    }

    /// The label on a row that has never been exported.
    static func draftLabel(locale: Locale = .current) -> String {
        String(
            localized: "Draft", table: VideoStudioCopy.table, locale: locale,
            comment: "Video Projects: label on a video project that has never been exported"
        )
    }

    /// The menu action on a draft row (FS-12.18 §4).
    static func deleteDraftLabel(locale: Locale = .current) -> String {
        String(
            localized: "Delete Draft", table: VideoStudioCopy.table, locale: locale,
            comment: "Video Projects: menu action that deletes a video draft — never the photos or videos it uses"
        )
    }

    static func deleteDraftTitle(locale: Locale = .current) -> String {
        String(
            localized: "Delete Draft?", table: VideoStudioCopy.table, locale: locale,
            comment: "Video Projects: title of the confirmation before a draft is deleted"
        )
    }

    static func deleteDraftMessage(locale: Locale = .current) -> String {
        String(
            localized: "The photos and videos stay in your library.", table: VideoStudioCopy.table, locale: locale,
            comment: "Video Projects: message of the Delete Draft confirmation — deleting a draft never touches the library"
        )
    }

    static func relativeTime(of creation: Creation, now: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = locale
        return formatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(creation.updatedAt)),
            relativeTo: now
        )
    }
}
