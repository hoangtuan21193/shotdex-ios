import Foundation
import ImageIO
import Photos
import UIKit

/// What Collage, Combine Photos and the Video Studio read from a server
/// original already on this device (FS-17.06 §5b) — the file-side twin of the
/// PhotoLibraryService requests they make for a library photo.
///
/// Everything here decodes at the size asked for: a 6000×4000 RAW becomes a
/// 1600-pixel preview without the full frame ever being in memory (AC-84).
enum PhotoOriginFile {
    /// The picture at a long side of at most `maxPixelSize`, orientation
    /// applied. Nil when ImageIO cannot open the file.
    static func image(at url: URL, maxPixelSize: Int) -> CGImage? {
        EmbeddedPreview.thumbnail(ofFileAt: url, maxPixelSize: max(1, maxPixelSize))?.image
    }

    /// `image(at:maxPixelSize:)` off the main thread.
    static func loadImage(at url: URL, maxPixelSize: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            image(at: url, maxPixelSize: maxPixelSize).map { UIImage(cgImage: $0) }
        }.value
    }

    /// The image properties (EXIF, GPS, TIFF…) of the first image.
    static func properties(at url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    /// The capture time the camera wrote, read from the head of the file the
    /// way the server grid reads it (FS-17.01).
    static func captureDate(at url: URL, headBytes: Int = 1 << 20) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headBytes), !head.isEmpty else { return nil }
        return EmbeddedPreview.captureDate(from: head)
    }
}

extension PhotoEditOrigin {
    /// The name the photo goes by: the server file's, or the library
    /// original's.
    var filename: String {
        switch self {
        case .asset(let asset):
            PHAssetResource.assetResources(for: asset).first?.originalFilename ?? asset.localIdentifier
        case .serverFile(let photo):
            photo.photo.primary.name
        case .fileCopy(let file):
            file.url.lastPathComponent
        }
    }

    /// When it was taken: the asset's date, or the EXIF date in the file.
    var captureDate: Date? {
        switch self {
        case .asset(let asset): asset.creationDate
        case .serverFile(let photo): PhotoOriginFile.captureDate(at: photo.primaryURL)
        case .fileCopy(let file): PhotoOriginFile.captureDate(at: file.url)
        }
    }
}
