import Foundation

/// Words of export presets (FS-12.16). Preset names are app constants
/// (`VideoExportPreset.name`), the same in every language, as the places
/// they name are.
extension VideoStudioCopy {
    /// "Export for Reels / TikTok"
    static func exportFor(_ name: String) -> String {
        String(localized: "Export for \(name)", table: table, comment: "Video Studio Export Video: the export button, naming the chosen preset")
    }

    /// "YOUR PROJECT IS 16:9"
    static func yourProjectIs(_ ratio: String) -> String {
        String(localized: "YOUR PROJECT IS \(ratio)", table: table, comment: "Video Studio Export Video: the header over Fit on Background · Fill (Crop) when the preset's ratio is not the project's")
    }

    /// "Your Project Is 16:9" — the iPad sheet's Title Case.
    static func yourProjectIsTitle(_ ratio: String) -> String {
        String(localized: "Your Project Is \(ratio)", table: table, comment: "Video Studio iPad Export Video: the section title over Fit on Background · Fill (Crop)")
    }

    static var whereIsItGoing: String {
        String(localized: "Where Is It Going", table: table, comment: "Video Studio iPad Export Video: the title over the export presets")
    }

    static func exportFraming(_ framing: VideoFraming) -> String {
        switch framing {
        case .fit: String(localized: "Fit on Background", table: table, comment: "Video Studio Export Video: the project's frame whole, on its background, inside the preset's frame")
        case .fill: String(localized: "Fill (Crop)", table: table, comment: "Video Studio Export Video: the preset's frame filled, the project cropped from the middle")
        }
    }

    static var customExportShort: String {
        String(localized: "Any ratio · 720p–4K · 24/30/60", table: table, comment: "Video Studio Export Video: the Custom row's line before Video Settings are known")
    }

    static var railExportNote: String {
        String(localized: "Export in the rail uses the chosen preset.", table: table, comment: "Video Studio Duo cover Export Video: under the presets — the rail's Export button exports with the chosen one")
    }

    /// "0:24 · H.264 · saved to Photos, then Share"
    static func exportInfoLine(length: String, codec: String, isServerRun: Bool) -> String {
        isServerRun
            ? String(localized: "\(length) · \(codec) · then choose where it goes", table: table, comment: "Video Studio iPad Export Video: the line under Fit · Fill for server photos")
            : String(localized: "\(length) · \(codec) · saved to Photos, then Share", table: table, comment: "Video Studio iPad Export Video: the line under Fit · Fill — length, codec, where it goes")
    }

    /// VoiceOver: "Reels / TikTok, 1080 by 1920, 30 frames per second,
    /// about 30 megabytes" (AC-13); the selected trait says the rest.
    static func presetAccessibility(_ preset: VideoExportPreset, megabytes: Int) -> String {
        let size = preset.frameSize
        let codec = preset.codec == .h264 ? "" : ", \(preset.codec.displayName)"
        // Sizes as plain digits — "1080 by 1920", not "1,080".
        let width = String(Int(size.width)), height = String(Int(size.height))
        return String(
            localized: "\(preset.name), \(width) by \(height), \(preset.frameRate.rawValue) frames per second\(codec), about \(megabytes) megabytes",
            table: table,
            comment: "Video Studio Export Video: VoiceOver label of a preset row — name, size, rate, codec when not H.264, estimate"
        )
    }
}
