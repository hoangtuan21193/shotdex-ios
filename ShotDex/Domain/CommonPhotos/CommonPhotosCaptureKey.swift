import Foundation
import ImageIO

/// The capture time a photo's head names, as a key two copies of one shot
/// share (FS-19.08 §5 step 3): `DateTimeOriginal`, its fraction of a second
/// and the camera model. Only a hint toward Likely the same — two shots of a
/// burst can share it, and nothing is copied until the bytes match.
///
/// A head ImageIO cannot read (CR3, RAF and other RAW heads) gives no key:
/// the date string found in the raw bytes is often `DateTime`, carries no
/// fraction and no camera, and would make two bodies firing in the same
/// second look alike. Those files are still hashed — only not hinted.
enum CommonPhotosCaptureKey {
    /// How much of the file is read for it.
    static let headLength = 64 * 1024

    static func key(fromHead head: Data) -> String? {
        let source = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(source, head as CFData, false)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let subsec = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String ?? ""
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let model = tiff?[kCGImagePropertyTIFFModel] as? String, !model.isEmpty else { return nil }
        return [original, subsec, model].joined(separator: "|")
    }
}
