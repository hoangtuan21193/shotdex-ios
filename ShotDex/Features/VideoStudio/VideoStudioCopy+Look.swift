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
