import Foundation

/// Export presets (FS-12.16): where the next export goes. The choice lives
/// in the recipe — so it is saved with the draft and comes back — but is
/// never an undo step: it changes no picture of the project (§6, plan K5).
extension VideoStudioModel {
    /// The preset or Custom chosen; an id this build cannot read is the
    /// preset of the project's ratio (AC-12).
    var exportTarget: VideoExportTarget {
        VideoExportTarget.resolve(storedID: recipe.exportTarget, aspect: recipe.aspect)
    }

    /// Fit on Background or Fill (Crop) — Fill unless chosen.
    var exportFraming: VideoFraming { recipe.exportFraming ?? .fill }

    /// What the export will write.
    var exportSpec: VideoExportSpec {
        VideoExportSpec.make(target: exportTarget, framing: exportFraming, recipe: recipe)
    }

    /// The preset's ratio is not the project's: YOUR PROJECT IS 16:9 and
    /// Fit · Fill are shown.
    var exportNeedsFraming: Bool { exportSpec.framing != nil }

    /// A row chosen. Not an undo step (AC-8). YouTube 4K refuses while
    /// the 4K gate is shut (AC-6).
    func chooseExportTarget(_ target: VideoExportTarget) {
        if case .preset(let preset) = target, preset.resolution == .uhd4K, fourKVerdict != .allowed { return }
        guard recipe.exportTarget != target.storedID else { return }
        recipe.exportTarget = target.storedID
        markEdited()
    }

    func setExportFraming(_ framing: VideoFraming) {
        guard recipe.exportFraming != framing else { return }
        recipe.exportFraming = framing
        markEdited()
    }

    /// Custom: opens Video Settings and makes Custom the destination
    /// (§3, AC-7).
    func chooseCustomExport() {
        chooseExportTarget(.custom)
        openVideoSettingsFromExport()
    }

    /// A row's size estimate: the formula of FS-12.10 with its numbers.
    func estimatedBytes(for target: VideoExportTarget) -> Int64 {
        VideoExportSpec.make(target: target, framing: exportFraming, recipe: recipe).estimatedBytes(duration: totalDuration)
    }

    /// "Custom" row's line: the project's settings — "4:3 · 720p · 24 fps · H.264".
    var customExportLine: String {
        "\(recipe.aspect.displayName) · \(recipe.resolution.displayName) · \(VideoStudioCopy.framesPerSecond(recipe.frameRate.rawValue)) · \(recipe.codec.displayName)"
    }

    /// Why YouTube 4K is dimmed, when it is.
    var fourKPresetRefusal: String? {
        VideoStudioCopy.fourKReason(fourKVerdict)
    }

    /// "Export for Reels / TikTok"; Custom: "Export".
    var exportButtonTitle: String {
        switch exportTarget {
        case .preset(let preset): VideoStudioCopy.exportFor(preset.name)
        case .custom: VideoStudioCopy.export
        }
    }

    /// The iPad's Video Settings button while Export Video is open (AC-15):
    /// what will be written — "9:16 · 1080p · 30 fps".
    var exportTargetSettingsLine: String {
        switch exportTarget {
        case .preset(let preset):
            "\(preset.aspect.displayName) · \(preset.resolution.displayName) · \(VideoStudioCopy.framesPerSecond(preset.frameRate.rawValue))"
        case .custom:
            "\(recipe.aspect.displayName) · \(recipe.resolution.displayName) · \(VideoStudioCopy.framesPerSecond(recipe.frameRate.rawValue))"
        }
    }
}
