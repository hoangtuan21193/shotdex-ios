import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Grid thumbnails of file photos (FS-19.01b §5): 400px on the long edge,
/// taken from the preview the camera embedded (never a RAW decode), kept in
/// the shared preview cache so an unplugged drive still shows its photos.
struct FolderThumbnails: Sendable {
    static let longEdge = 400
    /// Below this much free space the cache stops writing; metadata reads go
    /// on. Kept well above zero so the volume never fills to the brim.
    static let reserveBytes: Int64 = 512 * 1024 * 1024

    let directory: URL
    /// Free bytes on the cache's volume; injected for tests.
    let availableBytes: @Sendable () -> Int64?

    enum Outcome: Equatable, Sendable {
        case written
        case noPreview
        case noSpace
    }

    static var standard: FolderThumbnails {
        let directory = PreviewCacheLocation.standard.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return FolderThumbnails(directory: directory) {
            let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values?.volumeAvailableCapacityForImportantUsage
        }
    }

    func url(copyId: String) -> URL { directory.appendingPathComponent(copyId + ".jpg") }

    func write(from file: URL, copyId: String) -> Outcome {
        if let free = availableBytes(), free < Self.reserveBytes { return .noSpace }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceThumbnailMaxPixelSize: Self.longEdge,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                ?? CGImageSourceCreateThumbnailAtIndex(source, 0, options.merging([kCGImageSourceCreateThumbnailFromImageIfAbsent: true]) { $1 } as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(url(copyId: copyId) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return .noPreview }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? .written : .noPreview
    }
}
