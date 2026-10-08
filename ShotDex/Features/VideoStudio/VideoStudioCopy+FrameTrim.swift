import Foundation

/// Words of the frame trim and Frame zoom (FS-12.17): one name for the mode
/// on every device — "Trim · Clip 2" over "0:09.07 · −4 frames". Counts go
/// through the table's plural variations, never through concatenation.
extension VideoStudioCopy {
    /// "Trim · Clip 2": the footer while an edge is being trimmed.
    static func frameTrimTitle(_ itemName: String) -> String {
        String(localized: "Trim · \(itemName)", table: table, comment: "Video Studio frame trim: the footer's title — the mode, then the clip whose edge moves (e.g. Trim · Clip 2)")
    }

    /// "−4 frames", "+1 frame", "0 frames" — how far the edge moved since
    /// the trim began; "−4 f" where the row is narrow (Duo inner display,
    /// the loupe on the phone).
    static func frameCount(_ frames: Int, compact: Bool = false) -> String {
        let sign = frames < 0 ? "−" : (frames > 0 ? "+" : "")
        let count = abs(frames)
        let words = compact
            ? String(localized: "\(count) f", table: table, comment: "Video Studio frame trim: a short count of frames, after a sign (−4 f) — the narrow form")
            : String(localized: "\(count) frames", table: table, comment: "Video Studio frame trim: how many frames the edge moved, after a sign (−4 frames) (plural)")
        return sign + words
    }

    /// "Last frame · 0:09.07" / "First frame · 0:03.00": the viewer's
    /// label while trimming — which frame it shows, and where.
    static func edgeFrameLabel(trailing: Bool, at time: String) -> String {
        trailing
            ? String(localized: "Last frame · \(time)", table: table, comment: "Video Studio frame trim: the label over the viewer — it shows the clip's last frame, at this time")
            : String(localized: "First frame · \(time)", table: table, comment: "Video Studio frame trim: the label over the viewer — it shows the clip's first frame, at this time")
    }

    static var minusOneFrame: String {
        String(localized: "−1 Frame", table: table, comment: "Video Studio frame trim: moves the trimmed edge one frame earlier")
    }

    static var plusOneFrame: String {
        String(localized: "+1 Frame", table: table, comment: "Video Studio frame trim: moves the trimmed edge one frame later")
    }

    /// VoiceOver's name for a clip's edge handle: "Clip 2 end",
    /// "Clip 2 start" (AC-14).
    static func edgeHandleName(_ itemName: String, trailing: Bool) -> String {
        trailing
            ? String(localized: "\(itemName) end", table: table, comment: "VoiceOver: a clip's trailing edge handle on the Video Studio timeline (e.g. Clip 2 end); adjustable a frame at a time")
            : String(localized: "\(itemName) start", table: table, comment: "VoiceOver: a clip's leading edge handle on the Video Studio timeline (e.g. Clip 2 start); adjustable a frame at a time")
    }

    /// The loupe when the clip's media is not on this device (§10).
    static var offline: String {
        String(localized: "Offline", table: table, comment: "Video Studio frame trim: the loupe cannot show frames — the clip is not downloaded and there is no network")
    }
}
