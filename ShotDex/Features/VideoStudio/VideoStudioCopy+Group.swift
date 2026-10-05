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

    /// A group control whose clips differ: Speed, Look.
    static var mixed: String {
        String(localized: "Mixed", table: table, comment: "Video Studio multi-select: the value of a control whose selected clips are set differently — Speed Mixed, Look Mixed")
    }

    /// The line under the group's Speed when it holds stills (FS-12.11 §5):
    /// "Applies to the 2 videos · the photo keeps its 3.0s". Nil for a group
    /// of videos only.
    static func speedNote(videos: Int, stills: [VideoClip]) -> String? {
        guard videos > 0, !stills.isEmpty else { return nil }
        let applies = String(localized: "Applies to the \(videos) videos", table: table, comment: "Video Studio multi-select: under Speed, which clips it changes — Applies to the 2 videos; one: Applies to the video (plural)")
        let keeps: String = if stills.count == 1 {
            String(localized: "the photo keeps its \(String(format: "%.1fs", stills[0].effectiveDuration))", table: table, comment: "Video Studio multi-select: under Speed, the one still it leaves alone — the photo keeps its 3.0s")
        } else {
            String(localized: "the \(stills.count) photos keep their length", table: table, comment: "Video Studio multi-select: under Speed, the stills it leaves alone — the 2 photos keep their length (plural)")
        }
        return "\(applies) · \(keeps)"
    }

    /// "Move 2 clips here": the pill over the drop line, and the button
    /// that drops when Move is used without a drag.
    static func moveClipsHere(_ count: Int) -> String {
        String(localized: "Move \(count) clips here", table: table, comment: "Video Studio multi-select: the pill over the drop line — where the selected clips will go (plural)")
    }

    /// VoiceOver's reading of the pill: "3 selected, 14.2 seconds".
    static func groupPillLabel(count: Int, seconds: Double) -> String {
        String(localized: "\(count) selected, \(String(format: "%.1f", seconds)) seconds", table: table, comment: "Video Studio multi-select: VoiceOver name of the pill over the timeline — how many clips are selected and how long they run (plural)")
    }
}
