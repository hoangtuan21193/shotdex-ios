import Foundation
import GRDB

/// What a photo grid cell needs to render: identity, date (section headers)
/// and the exposure fields of the tile overlay. Lets the shared grid serve
/// both the Library (slim `LibraryGridItem` rows) and Albums (full
/// `PhotoMetadata` rows) without copying full metadata for every photo.
protocol PhotoGridDisplayable {
    var assetId: String { get }
    var creationDateValue: Date? { get }
    var iso: Int? { get }
    var aperture: Double? { get }
    var shutterSpeedDisplay: String? { get }
    var focalLength: Double? { get }
    var equivalentFocalLength: Double? { get }
    /// Sensor resolution in megapixels (from stored pixel dimensions), nil
    /// when unknown. File size in bytes, nil until the EXIF pass fills it.
    var megapixels: Double? { get }
    var fileSize: Int? { get }
}

/// Slim projection of one `photo_metadata` row: exactly what the Library
/// grid renders. The whole filtered library is loaded at once as these
/// (~200 KB per 1k photos), so the grid never pages — LazyVGrid virtualizes
/// rendering and memory stays flat no matter how far the user scrolls.
struct LibraryGridItem: Codable, Equatable, Identifiable, Sendable, FetchableRecord {
    var assetId: String
    var creationDate: Int?
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

extension LibraryGridItem: PhotoGridDisplayable {}
extension PhotoMetadata: PhotoGridDisplayable {}
