import Foundation

/// Whether an import candidate is a still image or a video — decides the
/// PhotoKit resource type on import, the thumbnail path, and the EXIF pass
/// (videos are indexed with no EXIF, mirroring `IndexPipeline`).
enum ImportMediaKind: Sendable {
    case image
    case video
}

/// One media file discovered on an external volume (SD card / USB / folder),
/// a candidate for import into the photo library. Cheap facts (name, type,
/// size, file date) are filled during the fast folder scan; `metadata` starts
/// as a filename-only placeholder and is upgraded to a fully-composed
/// `PhotoMetadata` by the background EXIF pass so advanced (camera/lens/ISO)
/// filtering becomes available.
struct ImportCandidate: Identifiable, Sendable {
    /// File path — stable and unique within a scan; also used as the synthetic
    /// `PhotoMetadata.assetId` for in-memory filtering.
    var id: String { url.path }
    let url: URL
    let filename: String
    let kind: ImportMediaKind
    /// Recognized image type by extension; nil for videos.
    let fileType: PhotoFileType?
    let fileSize: Int?
    /// File creation/modification date (EXIF capture date is not read in the
    /// fast pass); used for date filters and newest-first ordering.
    let creationDate: Date?
    /// Filename-only placeholder after the scan; full EXIF-composed row after
    /// the background pass. Always non-nil so filename/type/date rules match
    /// immediately; camera/lens/ISO rules match once EXIF has been read.
    var metadata: PhotoMetadata

    /// True for RAW/DNG files — hidden by default (the whole point of the
    /// filtered importer: skip RAW, keep JPEG/HEIC). Videos are never RAW.
    var isRaw: Bool { fileType?.isRawFormat ?? false }

    /// Video container extensions the importer recognizes (camera + phone).
    static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mts", "m2ts", "3gp", "3g2", "mpg", "mpeg", "wmv",
    ]

    /// Classifies a file by extension into a media kind (+ image file type),
    /// or nil if it is neither a recognized image nor video.
    static func classify(url: URL) -> (kind: ImportMediaKind, fileType: PhotoFileType?)? {
        if let type = PhotoFileType.classify(extension: url.pathExtension) {
            return (.image, type)
        }
        if videoExtensions.contains(url.pathExtension.lowercased()) {
            return (.video, nil)
        }
        return nil
    }
}

extension PhotoFileType {
    /// Classifies a lowercased filename extension to its type. Order matters:
    /// specific image types first, `.dng` before the generic `.raw` bag (which
    /// also lists `dng`), so a `.dng` file reports as DNG rather than RAW.
    static func classify(extension fileExtension: String) -> PhotoFileType? {
        let lower = fileExtension.lowercased()
        let order: [PhotoFileType] = [.jpeg, .heic, .png, .tiff, .gif, .dng, .raw]
        return order.first { $0.extensions.contains(lower) }
    }

    /// Whether this type is a raw capture format (RAW bag or DNG).
    var isRawFormat: Bool { self == .raw || self == .dng }
}
