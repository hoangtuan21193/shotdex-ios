import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ShotDexKit

/// The FS-05.04 §7 fixtures, made here: preset **Credit** (a white line
/// `© Nguyen An · {camera}` and a 400×400 PNG logo, saved on a 3:2 landscape
/// photo), configuration **W**, and plain landscape photos. A gradient with
/// stripes — no face, no real photo.
enum WatermarkFixture {
    static let creditText = "© Nguyen An · {camera}"

    /// Configuration W: bottom right, Margin 3%, Size 4%, Opacity 100%.
    static let placementW = WatermarkPlacement(anchor: .bottomRight, margin: 0.03, size: 0.04, opacity: 1)

    /// A 400×400 logo: an orange disc on transparent pixels, stored where the
    /// renderer looks for signature images. Remove it with `removeLogo`.
    static func storeLogo(in store: OverlayImageStore = OverlayImageStore()) throws -> UUID {
        let context = CGContext(
            data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 20, y: 20, width: 360, height: 360))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return try store.store(pngData: data as Data)
    }

    /// Preset Credit: the credit line, and the logo to its right.
    static func credit(logo: UUID?, id: UUID = UUID()) -> SignaturePreset {
        var text = PhotoOverlay.text()
        text.text = creditText
        text.size = 0.03
        text.center = NormalizedPoint(x: 0.78, y: 0.93)
        var layers = [text]
        if let logo {
            var image = PhotoOverlay.image(id: logo, assetIdentifier: nil)
            image.size = 0.06
            image.center = NormalizedPoint(x: 0.95, y: 0.93)
            layers.append(image)
        }
        return SignaturePreset(
            id: id, name: "Credit", createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            layers: layers, sourceAspect: 1.5
        )
    }

    /// A landscape JPEG, orientation 1, no metadata beyond what is asked.
    static func jpeg(width: Int, height: Int, in folder: URL, properties: [CFString: Any] = [:]) throws -> URL {
        let url = folder.appendingPathComponent("W-\(UUID().uuidString.prefix(8)).jpg")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        var options = properties
        options[kCGImageDestinationLossyCompressionQuality] = 0.9
        CGImageDestinationAddImage(destination, image(width: width, height: height), options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    /// A sky-to-ground gradient with fine stripes, so a resize and a re-encode
    /// both have detail to change.
    static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [
                CGColor(red: 0.35, green: 0.47, blue: 0.62, alpha: 1),
                CGColor(red: 0.78, green: 0.71, blue: 0.59, alpha: 1),
                CGColor(red: 0.30, green: 0.41, blue: 0.24, alpha: 1),
            ] as CFArray,
            locations: [0, 0.6, 1]
        )!
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: []
        )
        context.setFillColor(CGColor(gray: 0, alpha: 0.12))
        var x = 0
        while x < width {
            context.fill(CGRect(x: x, y: 0, width: max(1, width / 600), height: height))
            x += max(3, width / 150)
        }
        return context.makeImage()!
    }

    /// RGBA8 sRGB pixels of a CIImage over its extent, top row first.
    static func pixels(of image: CIImage, context: CIContext = CIContext()) -> (data: [UInt8], width: Int, height: Int) {
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            image, toBitmap: &data, rowBytes: width * 4, bounds: extent,
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return (data, width, height)
    }

    /// RGBA8 sRGB pixels of an image file, top row first.
    static func pixels(of url: URL) -> (data: [UInt8], width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return pixels(of: image)
    }

    /// RGBA8 sRGB pixels of a CGImage, top row first.
    static func pixels(of image: CGImage) -> (data: [UInt8], width: Int, height: Int) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (data, width, height)
    }

    /// Pixels that differ between `a` and `b`, counted outside `excluded`
    /// (top-down) and inside it.
    static func differences(
        _ a: [UInt8], _ b: [UInt8], width: Int, height: Int, excluding excluded: CGRect
    ) -> (outside: Int, inside: Int) {
        var outside = 0
        var inside = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] else { continue }
                if excluded.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                    inside += 1
                } else {
                    outside += 1
                }
            }
        }
        return (outside, inside)
    }

    /// `rect` grown outward to the 16-pixel grid JPEG encodes in.
    static func blockAligned(_ rect: CGRect) -> CGRect {
        let minX = (rect.minX / 16).rounded(.down) * 16
        let minY = (rect.minY / 16).rounded(.down) * 16
        let maxX = (rect.maxX / 16).rounded(.up) * 16
        let maxY = (rect.maxY / 16).rounded(.up) * 16
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
