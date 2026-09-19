import Foundation
import GRDB

/// What a photo grid cell needs to render: identity, date (section headers),
/// file type and exposure fields. Lets the shared grid serve both the Library
/// (slim `LibraryGridItem` rows) and Albums (full `PhotoMetadata` rows)
/// without copying full metadata for every photo.
protocol PhotoGridDisplayable {
    var assetId: String { get }
    var creationDateValue: Date? { get }
    /// Raw PhotoKit media type (1 = image, 2 = video) and the indexed source
    /// filename used by the file-type badge.
    var mediaType: Int { get }
    var originalFilename: String? { get }
    var iso: Int? { get }
    var aperture: Double? { get }
    var shutterSpeedDisplay: String? { get }
    var focalLength: Double? { get }
    var equivalentFocalLength: Double? { get }
    /// Sensor resolution in megapixels (from stored pixel dimensions), nil
    /// when unknown. File size in bytes, nil until the EXIF pass fills it.
    var megapixels: Double? { get }
    var fileSize: Int? { get }
    /// Stored pixel dimensions (orientation-corrected), for the 1-column
    /// aspect-ratio layout. Nil until the index records them.
    var pixelWidth: Int? { get }
    var pixelHeight: Int? { get }
}

/// The photographer-facing name for a file format, shared by the grid tile's
/// badge and the Info panel's per-file sections — one dictionary, so RAW does
/// not group one way on a tile and another way in a report.
enum FileTypeBadge {
    /// RAW container extensions are deliberately grouped as "RAW"; common
    /// rendered formats keep their familiar short name.
    static func text(forExtension fileExtension: String) -> String? {
        let normalized = fileExtension.uppercased()
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "3FR", "ARW", "CR2", "CR3", "CRW", "DCR", "DNG", "ERF",
             "IIQ", "KDC", "MEF", "MOS", "MRW", "NEF", "NRW", "ORF",
             "PEF", "RAF", "RAW", "RW2", "RWL", "SR2", "SRF", "SRW", "X3F":
            return "RAW"
        case "JPEG", "JPE":
            return "JPG"
        case "HEIF", "HIF":
            return "HEIC"
        case "TIF":
            return "TIFF"
        default:
            // Avoid an unusual/invalid extension expanding across a dense tile.
            return String(normalized.prefix(6))
        }
    }
}

extension PhotoGridDisplayable {
    /// Compact, photographer-facing file category for the tile's top-leading
    /// badge.
    var fileTypeBadgeText: String {
        let kindBadge = MediaKind(storedValue: mediaType) == .video ? "VIDEO" : "PHOTO"

        guard let filename = originalFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
              !filename.isEmpty
        else {
            return kindBadge
        }

        let fileExtension = URL(fileURLWithPath: filename).pathExtension
        return FileTypeBadge.text(forExtension: fileExtension) ?? kindBadge
    }
}

/// Slim projection of one `photo_metadata` row: exactly what the Library
/// grid renders. The whole filtered library is loaded at once as these
/// (~200 KB per 1k photos), so the grid never pages — LazyVGrid virtualizes
/// rendering and memory stays flat no matter how far the user scrolls.
struct LibraryGridItem: Codable, Equatable, Identifiable, Sendable, FetchableRecord {
    var assetId: String
    var creationDate: Int?
    var mediaType: Int
    var originalFilename: String?
    var iso: Int?
    var aperture: Double?
    var shutterSpeedDisplay: String?
    var focalLength: Double?
    var equivalentFocalLength: Double?
    var width: Int?
    var height: Int?
    var fileSize: Int?

    var id: String { assetId }

    var creationDateValue: Date? {
        creationDate.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var megapixels: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width * height) / 1_000_000
    }
}

extension LibraryGridItem: PhotoGridDisplayable {
    var pixelWidth: Int? { width }
    var pixelHeight: Int? { height }
}

extension PhotoMetadata: PhotoGridDisplayable {
    var pixelWidth: Int? { width }
    var pixelHeight: Int? { height }
}
