#if canImport(UIKit)
import UIKit

/// The platform's image type (FS-18 K2): `UIImage` on iOS, `NSImage` on the
/// Mac. Shared code that hands an image to a view uses this; new Domain code
/// takes and returns `CGImage` instead.
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#else
import AppKit

typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont

/// Draws into a fresh top-left-origin bitmap with AppKit's text and path
/// drawing current, the way `UIGraphicsImageRenderer` does on iOS.
enum PlatformDrawing {
    static func image(size: CGSize, _ draw: (CGContext) -> Void) -> CGImage? {
        let width = Int(size.width.rounded(.up)), height = Int(size.height.rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw(context)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

extension NSImage {
    /// `UIImage(cgImage:)`'s spelling, at the image's pixel size.
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// `UIImage.cgImage`'s spelling.
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// `UIImage(data:)` already exists as `NSImage(data:)`; this is `size`
    /// in pixels for the one caller that reads `scale`.
    var scale: CGFloat { 1 }
}
#endif
