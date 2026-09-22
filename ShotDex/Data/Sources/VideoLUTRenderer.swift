import CoreImage
import Foundation
import ShotDexKit

/// Applies an imported `.cube` LUT to a frame.
///
/// One `CIColorCubeWithColorSpace` pass in sRGB, for the same reason the
/// film looks take that path: a `.cube` is authored against gamma-encoded
/// code values, not against light, so running it in the context's linear
/// working space would apply the right table to the wrong numbers.
enum VideoLUTRenderer {
    /// `image` graded through `lut` at its intensity, or `image` unchanged
    /// when the table is missing or the intensity is zero.
    static func apply(
        _ reference: VideoLUTReference?,
        url: URL?,
        to image: CIImage
    ) -> CIImage {
        guard let reference, let url,
              let lut = LUTTableCache.shared.table(id: reference.id, url: url)
        else { return image }
        return PhotoRenderService.applyLUT(lut, intensity: reference.intensity, to: image)
    }
}
