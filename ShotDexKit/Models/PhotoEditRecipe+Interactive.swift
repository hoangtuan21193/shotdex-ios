import Foundation

/// The recipe a preview draws while a finger is still moving (FS-03.18 §1):
/// Lightroom renders a lower-quality proxy during tracking and the final
/// quality on release (`makeProxyImage`, `lowQuality`,
/// `allowGPUAndCPURendersOnTrackingStop`). The stages that cost the most per
/// frame and change the least of what a slider drag is judging — sharpening,
/// noise reduction, grain — step aside until release. Never used to save.
public enum InteractiveDraft {
    /// Sharpening and noise reduction: the Detail panel.
    public static let detailKinds: Set<PhotoAdjustmentKind> = [
        .sharpness, .sharpenRadius, .sharpenDetail, .sharpenMasking,
        .noiseReduction, .noiseDetail, .noiseContrast,
        .colorNoiseReduction, .colorNoiseDetail, .colorNoiseSmoothness,
    ]
    /// Film grain.
    public static let grainKinds: Set<PhotoAdjustmentKind> = [.grain, .grainSize, .grainRoughness]

    /// The strength sliders of those groups — zero turns the stage off.
    static let detailStrengths: [PhotoAdjustmentKind] = [.sharpness, .noiseReduction, .colorNoiseReduction]
    static let grainStrengths: [PhotoAdjustmentKind] = [.grain]
}

extension PhotoEditRecipe {
    /// This recipe with sharpening, noise reduction and grain switched off —
    /// except the group the moving control belongs to, so dragging Sharpness
    /// still shows sharpening.
    public func interactiveDraft(editing kind: PhotoAdjustmentKind?) -> PhotoEditRecipe {
        var draft = self
        if kind.map({ !InteractiveDraft.detailKinds.contains($0) }) ?? true {
            for strength in InteractiveDraft.detailStrengths {
                draft.adjustments[strength] = PhotoAdjustments.zero[strength]
            }
        }
        if kind.map({ !InteractiveDraft.grainKinds.contains($0) }) ?? true {
            for strength in InteractiveDraft.grainStrengths {
                draft.adjustments[strength] = PhotoAdjustments.zero[strength]
            }
        }
        return draft
    }
}
