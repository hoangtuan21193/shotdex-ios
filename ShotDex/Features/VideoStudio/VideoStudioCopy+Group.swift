import Foundation

/// Words of multi-select (FS-12.11): the footer, the pill on the lanes and
/// the iPad's play row. Counts go through the table's plural variations,
/// never through concatenation.
extension VideoStudioCopy {
    /// The group's Move command: moves the selected clips without a drag.
    static var move: String {
        String(localized: "Move", table: table, comment: "Video Studio multi-select: command that moves the selected clips to another place without dragging")
    }

    /// "1 Clip", "3 Clips": the footer's name for the group.
    static func clipCount(_ count: Int) -> String {
        String(localized: "\(count) Clips", table: table, comment: "Video Studio multi-select: the footer's name for the selected clips — 3 Clips (plural)")
    }

    /// "3 selected": the pill at the head of the lanes.
    static func selectedCount(_ count: Int) -> String {
        String(localized: "\(count) selected", table: table, comment: "Video Studio multi-select: the pill over the timeline — how many clips are selected (plural)")
    }

    /// "3 clips selected": the head of the iPad's play row while a group
    /// is selected, where "Clip 2 under playhead" stands otherwise.
    static func clipsSelected(_ count: Int) -> String {
        String(localized: "\(count) clips selected", table: table, comment: "Video Studio iPad multi-select: under the frame, at the head of the play row — how many clips are selected (plural)")
    }

    static func videoCount(_ count: Int) -> String {
        String(localized: "\(count) videos", table: table, comment: "Video Studio multi-select: how many of the selected clips are videos — 2 videos (plural)")
    }

    static func photoCount(_ count: Int) -> String {
        String(localized: "\(count) photos", table: table, comment: "Video Studio multi-select: how many of the selected clips are stills — 1 photo (plural)")
    }

    /// "14.2s · 2 videos + 1 photo" — or "14.2s" alone when the group is
    /// all one kind, or when `includesKinds` is off (the Duo's narrow
    /// footers).
    static func groupDetail(_ summary: VideoClipGroupEditing.Summary, includesKinds: Bool = true) -> String {
        let seconds = String(format: "%.1fs", summary.seconds)
        guard includesKinds, summary.videos > 0, summary.photos > 0 else { return seconds }
        let kinds = String(
            localized: "\(videoCount(summary.videos)) + \(photoCount(summary.photos))",
            table: table,
            comment: "Video Studio multi-select: the kinds in the group — 2 videos + 1 photo"
        )
        return "\(seconds) · \(kinds)"
    }
}
