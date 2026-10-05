import Foundation

/// The Look panel's words (FS-12.06c), in the Video Studio's own table.
extension VideoStudioCopy {
    /// VoiceOver, after a clip with a look of its own: "Look Night Teal".
    static func lookNamed(_ name: String) -> String {
        String(localized: "Look \(name)", table: table, comment: "Video Studio: VoiceOver, after a timeline clip that has a look of its own — the look's name follows")
    }
}

extension VideoStudioCopy {
    /// The line under Apply To (FS-12.06c §5): what of the chosen look a
    /// video frame does not run. Always there, so the panel never jumps.
    static func lookSkippedLine(_ names: [String]) -> String {
        guard !names.isEmpty else {
            return String(localized: "Everything in this look applies to video.", table: table, comment: "Video Studio Look panel: nothing in the chosen look is skipped on video")
        }
        let list = names.map(localizedSettingName).formatted(.list(type: .and, width: .narrow))
        return String(localized: "Skipped on video: \(list).", table: table, comment: "Video Studio Look panel: the settings of the chosen look a video frame does not run — e.g. Noise Reduction, Upright")
    }

    private static func localizedSettingName(_ name: String) -> String {
        switch name {
        case "Noise Reduction": String(localized: "Noise Reduction", table: table, comment: "Video Studio Look panel: a photo setting skipped on video")
        case "Upright": String(localized: "Upright", table: table, comment: "Video Studio Look panel: a photo setting skipped on video")
        case "Lens Correction": String(localized: "Lens Correction", table: table, comment: "Video Studio Look panel: a photo setting skipped on video")
        case "Texture": String(localized: "Texture", table: table, comment: "Video Studio Look panel: a photo setting skipped on video")
        case "Clarity": String(localized: "Clarity", table: table, comment: "Video Studio Look panel: a photo setting skipped on video")
        case "Dehaze": String(localized: "Dehaze", table: table, comment: "Video Studio Look panel: a photo setting skipped on video")
        case "Sharpening": String(localized: "Sharpening", table: table, comment: "Video Studio Look panel: a photo setting skipped on video")
        default: name
        }
    }
}

extension VideoStudioCopy {
    static var amount: String {
        String(localized: "Amount", table: table, comment: "Video Studio Look panel: how much of the chosen look is mixed in, 0–100")
    }

    static var applyTo: String {
        String(localized: "APPLY TO", table: table, comment: "Video Studio Look panel: header over All Clips · This Clip — where a tapped look goes")
    }

    /// The same header in the iPad's portrait dock, Title Case (FS-12.03b
    /// §1, board F5_IP_Looks).
    static var applyToTitle: String {
        String(localized: "Apply To", table: table, comment: "Video Studio iPad Look panel: header over All Clips · This Clip — where a tapped look goes")
    }

    /// Under Import Look… in the iPad dock's third column (F5_IP_Looks).
    static var clipLookExplainer: String {
        String(localized: "A clip with its own look uses it instead of the video look. Use Video Look hands it back.", table: table, comment: "Video Studio iPad Look panel, a clip selected: what a clip's own look means")
    }

    /// The same line while the panel shows the whole video's look.
    static var wholeVideoLookExplainer: String {
        String(localized: "Select a clip to give it its own look.", table: table, comment: "Video Studio iPad Look panel, nothing selected: how to give one clip a different look")
    }

    static var importLook: String {
        String(localized: "Import Look…", table: table, comment: "Video Studio Look panel: brings Lightroom presets, .shotdexlook files and .cube LUTs in from Files")
    }

    /// VoiceOver on a tile: "Look Moody Coast, imported from Lightroom".
    static func lookTileLabel(name: String, isImported: Bool) -> String {
        isImported
            ? String(localized: "Look \(name), imported from Lightroom", table: table, comment: "Video Studio Look panel: VoiceOver on a look tile brought in from a Lightroom preset")
            : String(localized: "Look \(name)", table: table, comment: "Video Studio Look panel: VoiceOver on a look tile")
    }
}

extension VideoLookTarget {
    var title: String {
        switch self {
        case .thisClip: String(localized: "This Clip", table: VideoStudioCopy.table, comment: "Video Studio Look panel: a tapped look goes to the clip under the playhead (or the selected clip)")
        case .selected: String(localized: "Selected", table: VideoStudioCopy.table, comment: "Video Studio Look panel: a tapped look goes to every selected clip")
        case .allClips: String(localized: "All Clips", table: VideoStudioCopy.table, comment: "Video Studio Look panel: a tapped look becomes the whole video's and clears every clip's own")
        }
    }
}

extension VideoStudioCopy {
    /// The Look panel's line when the chosen look's LUT file is gone (§6).
    static func lookMissingLUT(_ name: String) -> String {
        String(localized: "\(name) is missing. Import it again, then pick it in LUTs.", table: table, comment: "Video Studio Look panel: the chosen look's LUT file was deleted — e.g. Kodak 2383 is missing")
    }

    /// Over Export and in Video Settings (§6): "1 look is missing its LUT
    /// and exports without it." — plural in the catalog.
    static func looksMissingLUT(_ count: Int) -> String {
        String(localized: "\(count) looks are missing their LUT and export without it.", table: table, comment: "Video Studio Export: how many looks (the video's and clips' own) lost their LUT file; the export goes on without it")
    }
}

extension VideoStudioCopy {
    static var lookForThisClip: String {
        String(localized: "Look for This Clip", table: table, comment: "Video Studio: header of a selected clip's own look block")
    }

    static var useVideoLook: String {
        String(localized: "Use Video Look", table: table, comment: "Video Studio: drops a clip's own look so it follows the whole video's again")
    }

    static var useVideoLookForThisClip: String {
        String(localized: "Use Video Look for this clip", table: table, comment: "Video Studio: VoiceOver on the button that drops a clip's own look")
    }

    static var applyToRow: String {
        String(localized: "Apply to", table: table, comment: "Video Studio clip Look block: label before This Clip · Selected · All Clips")
    }
}
