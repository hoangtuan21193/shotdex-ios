import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Mattes the app worked out itself — Subject, Sky, Object, People, face
/// parts — kept on disk so reopening a photo reads them instead of running
/// Vision again (FS-03.15d §5). One 8-bit grey PNG per matte, at most 1536px
/// on the long edge, named by a hash of the matte's key: the photo, the area
/// and its parameters, the crop. Losing a file costs one recompute, never an
/// error.
public final class GeneratedMatteStore: @unchecked Sendable {
    public let directory: URL
    private static let longestEdge = 1536

    public init(directory: URL) {
        self.directory = directory
    }

    /// The store under Application Support, created on first use.
    public static func applicationSupport() -> GeneratedMatteStore? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return GeneratedMatteStore(directory: base.appendingPathComponent("GeneratedMattes", isDirectory: true))
    }

    func url(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("png")
    }

    /// The saved matte for `key`, or nil when there is none (or it is unreadable).
    public func read(_ key: String) -> CGImage? {
        let url = url(for: key)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Saves `matte` for `key`, shrunk to the store's longest edge first.
    public func write(_ matte: CGImage, for key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = Self.shrunk(matte) ?? matte
        guard let destination = CGImageDestinationCreateWithURL(
            url(for: key) as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    public func remove(_ key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    private static func shrunk(_ image: CGImage) -> CGImage? {
        let long = max(image.width, image.height)
        guard long > longestEdge else { return nil }
        let scale = Double(longestEdge) / Double(long)
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
