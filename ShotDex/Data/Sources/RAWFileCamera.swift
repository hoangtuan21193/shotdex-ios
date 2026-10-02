import Foundation
import ImageIO
import ShotDexKit

/// The camera a RAW file names in its header, normalized as the index does
/// (BD-05) — for a photo the index has not reached (FS-03.04b §3). Nil when
/// ImageIO can't read the header at all (AC-9) or it names no model.
enum RAWFileCamera {
    static func camera(at url: URL) -> RAWCamera? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        else { return nil }
        let make = tiff[kCGImagePropertyTIFFMake] as? String
        let model = tiff[kCGImagePropertyTIFFModel] as? String
        return RAWCamera(
            manufacturer: CameraNormalizer.normalizeManufacturer(make),
            model: CameraNormalizer.normalizeModel(model, manufacturer: make)
        )
    }

    /// The decoder's refusal of `url`, as the error that says what to do.
    static func error(for url: URL, filename: String?, release: OSRelease = .current) -> UnsupportedRAWError {
        UnsupportedRAWError(message: .make(
            cameraName: camera(at: url)?.displayName,
            filename: filename ?? url.lastPathComponent,
            iOSVersion: release.version
        ))
    }
}
