import CoreImage
import Foundation

/// Visualize Spots (FS-03.15c §3): the photo as a black-and-white edge map
/// where sensor dust stands out as white dots. A way of looking, never an
/// edit — it is drawn over the stage and goes nowhere near a render.
public enum SpotVisualizer {

    /// `threshold` 0…1 is the slider: higher is more sensitive, so more of
    /// the photo's small changes read white.
    public static func map(of image: CIImage, threshold: Double) -> CIImage {
        let extent = image.extent
        let grey = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        // What is left after taking away the smooth ground: specks and edges.
        let smooth = grey.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4])
            .cropped(to: extent)
        let detail = grey.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: smooth])
        // Gain grows with sensitivity: at 100 a 1% bump is white.
        let sensitivity = min(1, max(0, threshold))
        let gain = 4 + 96 * sensitivity * sensitivity
        return detail
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .applyingFilter("CIColorClamp")
            .cropped(to: extent)
    }
}
