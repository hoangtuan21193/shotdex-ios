import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads the depth map a Portrait photo carries alongside its pixels.
///
/// A Portrait capture stores a low-resolution disparity map as auxiliary image
/// data in the same file. Core Image can hand it back directly, which is what
/// `CIDepthBlurEffect` wants — no `AVDepthData` conversion, no pixel-buffer
/// juggling.
public enum DepthImageReader {

    /// Whether this file carries depth at all. Cheap: it reads the auxiliary
    /// data's header, not the picture.
    public static func hasDepth(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        for type in auxiliaryTypes {
            if CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) != nil {
                return true
            }
        }
        return false
    }

    /// The disparity map as a `CIImage`, oriented like the photo.
    ///
    /// Disparity rather than depth: the two are reciprocals, and Core Image's
    /// depth blur is written against disparity. Asking for the disparity
    /// option lets Core Image do that conversion for a file that only stores
    /// depth.
    public static func disparity(at url: URL) -> CIImage? {
        CIImage(
            contentsOf: url,
            options: [
                .auxiliaryDisparity: true,
                .applyOrientationProperty: true,
            ]
        ) ?? CIImage(
            contentsOf: url,
            options: [
                .auxiliaryDepth: true,
                .applyOrientationProperty: true,
            ]
        )
    }

    /// The portrait matte, when the capture has one. It marks the subject far
    /// more precisely than the depth map does around hair and edges, and the
    /// blur filter takes it as a separate input for exactly that.
    public static func matte(at url: URL) -> CIImage? {
        CIImage(
            contentsOf: url,
            options: [
                .auxiliaryPortraitEffectsMatte: true,
                .applyOrientationProperty: true,
            ]
        )
    }

    private static let auxiliaryTypes: [CFString] = [
        kCGImageAuxiliaryDataTypeDisparity,
        kCGImageAuxiliaryDataTypeDepth,
        kCGImageAuxiliaryDataTypePortraitEffectsMatte,
    ]
}
