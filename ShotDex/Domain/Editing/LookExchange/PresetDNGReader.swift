import Foundation
import ImageIO

/// A preset saved as a DNG (FS-03.14a §1): the XMP packet is read through
/// ImageIO's metadata alone — `kCGImageSourceShouldCache` off, no image ever
/// created — then handed to `LightroomXMPReader`. A 25 MB mobile preset costs
/// its metadata, not its pixels.
enum PresetDNGReader {
    /// How many times this reader has decoded pixels. The seam the test reads;
    /// nothing here ever increments it, and that is the point.
    nonisolated(unsafe) static var pixelDecodes = 0

    enum Failure: Error, Equatable {
        case notAnImage
        case noXMP

        var message: String {
            switch self {
            case .notAnImage: "This file isn't a DNG ShotDex can read"
            case .noXMP: "This DNG carries no preset settings"
            }
        }
    }

    static func read(url: URL) throws -> LightroomSettings {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { throw Failure.notAnImage }
        return try read(source)
    }

    static func read(data: Data) throws -> LightroomSettings {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { throw Failure.notAnImage }
        return try read(source)
    }

    private static func read(_ source: CGImageSource) throws -> LightroomSettings {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, options),
              let xmp = CGImageMetadataCreateXMPData(metadata, nil) as Data?
        else { throw Failure.noXMP }
        return try LightroomXMPReader.read(xmp)
    }
}
