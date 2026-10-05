import Foundation

/// Words of Before and After (FS-12.15).
extension VideoStudioCopy {
    static var before: String {
        String(localized: "Before", table: table, comment: "Video Studio compare: the label on the original frame, and VoiceOver's name for it and for the Split handle")
    }

    static var after: String {
        String(localized: "After", table: table, comment: "Video Studio compare: the label on the edited frame")
    }

    static var compareHeader: String {
        String(localized: "COMPARE", table: table, comment: "Video Studio Look panel: the header over Split · Hold to Compare")
    }

    static var compareTitle: String {
        String(localized: "Compare", table: table, comment: "Video Studio compare: the iPad dock's column title over Side by Side · Split")
    }

    static func compareMode(_ mode: VideoBeforeAfter.Mode) -> String {
        switch mode {
        case .sideBySide: String(localized: "Side by Side", table: table, comment: "Video Studio compare: the original and the edit as two frames")
        case .split: String(localized: "Split", table: table, comment: "Video Studio compare: one frame, the original left of a line the user drags")
        case .hold: String(localized: "Hold to Compare", table: table, comment: "Video Studio compare: holding a finger on the frame shows the original")
        }
    }

    /// "Both sides play and scrub together · 0:08.4"
    static func bothSidesPlay(_ short: Bool, at time: String) -> String {
        short
            ? String(localized: "Both sides play together · \(time)", table: table, comment: "Video Studio compare, Duo: under the two frames, with the playhead")
            : String(localized: "Both sides play and scrub together · \(time)", table: table, comment: "Video Studio compare: under the two frames, with the playhead")
    }

    static var noEditsToCompare: String {
        String(localized: "No edits to compare yet.", table: table, comment: "Video Studio compare: the project has no look, adjustments, color or overlays — both sides are the same")
    }

    static var splitHint: String {
        String(localized: "Drag the white line across the frame. Before drops the look, adjustments, color and overlays.", table: table, comment: "Video Studio Look panel: under COMPARE when Split is chosen")
    }

    static var holdHint: String {
        String(localized: "Hold a finger on the frame to see the original. Before drops the look, adjustments, color and overlays.", table: table, comment: "Video Studio Look panel: under COMPARE when Hold to Compare is chosen")
    }

    static var dragToCompare: String {
        String(localized: "Drag to compare", table: table, comment: "Video Studio compare: VoiceOver hint on the Split handle")
    }

    /// "50 percent"
    static func percentValue(_ percent: Int) -> String {
        String(localized: "\(percent) percent", table: table, comment: "Video Studio compare: VoiceOver value of the Split handle — how much of the frame is Before")
    }

    static var swapSides: String {
        String(localized: "Swap Sides", table: table, comment: "Video Studio compare, iPad portrait: puts After on the left and Before on the right")
    }

    static var beforeShows: String {
        String(localized: "Before shows", table: table, comment: "Video Studio compare, iPad portrait: the row saying what the Before side is")
    }

    static var originalClip: String {
        String(localized: "Original clip", table: table, comment: "Video Studio compare, iPad portrait: what the Before side shows")
    }

    static var beforeDropsNote: String {
        String(localized: "Before drops the look, adjustments, color and overlays — the same thing holding the frame shows.", table: table, comment: "Video Studio compare, iPad portrait: the note under the Compare column")
    }

    static var lookAmount: String {
        String(localized: "Amount", table: table, comment: "Video Studio compare, iPad portrait: how strongly the look applies")
    }

    static var adjustTitle: String {
        String(localized: "Adjust", table: table, comment: "Video Studio compare, iPad portrait: the column of exposure, contrast, saturation and warmth")
    }
}
