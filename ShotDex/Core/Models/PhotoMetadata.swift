import Foundation
import GRDB

/// Status of the EXIF extraction for an asset.
enum ExifStatus: String, Codable, Sendable {
    case indexed
    case noExif
    /// Row written by the fast pass (PHAsset facts only) — EXIF not read yet.
    case pendingRead
    case pendingICloud
    case error
}

/// One row of the `photo_metadata` table — the indexed metadata of a single PHAsset.
struct PhotoMetadata: Codable, Equatable, Identifiable, Sendable {
    var assetId: String
    var creationDate: Int?
    var modificationDate: Int?
    var mediaType: Int

    var cameraManufacturer: String?
    var cameraModel: String?
    var normalizedCameraModel: String?
    var normalizedCameraManufacturer: String?

    var lensManufacturer: String?
    var lensModel: String?
    var normalizedLensModel: String?

    var originalFilename: String? = nil

    var iso: Int?
    var aperture: Double?
    var shutterSpeedSeconds: Double?
    var shutterSpeedDisplay: String?

    var focalLength: Double?
    var focalLengthIn35mm: Double?
    var calculatedEquivalentFocalLength: Double?
    /// Denormalized "best" equivalent focal length used by queries:
    /// EXIF 35mm value when valid, otherwise the calculated one.
    var equivalentFocalLength: Double?

    var sensorFormat: String?
    var cropFactor: Double?

    var width: Int?
    var height: Int?
    var fileSize: Int?

    var latitude: Double?
    var longitude: Double?

    var isFavorite: Bool
    var indexedAt: Int
    var exifStatus: String

    var id: String { assetId }

    var megapixels: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width * height) / 1_000_000
    }

    var resolvedSensorFormat: SensorFormat {
        sensorFormat.flatMap(SensorFormat.init(rawValue:)) ?? .unknown
    }

    var resolvedExifStatus: ExifStatus {
        ExifStatus(rawValue: exifStatus) ?? .error
    }

    var creationDateValue: Date? {
        creationDate.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

extension PhotoMetadata: FetchableRecord, PersistableRecord {
    static let databaseTableName = "photo_metadata"

    enum Columns {
        static let assetId = Column(CodingKeys.assetId)
        static let creationDate = Column(CodingKeys.creationDate)
        static let modificationDate = Column(CodingKeys.modificationDate)
        static let normalizedCameraModel = Column(CodingKeys.normalizedCameraModel)
        static let normalizedCameraManufacturer = Column(CodingKeys.normalizedCameraManufacturer)
        static let normalizedLensModel = Column(CodingKeys.normalizedLensModel)
        static let iso = Column(CodingKeys.iso)
        static let aperture = Column(CodingKeys.aperture)
        static let shutterSpeedSeconds = Column(CodingKeys.shutterSpeedSeconds)
        static let focalLength = Column(CodingKeys.focalLength)
        static let equivalentFocalLength = Column(CodingKeys.equivalentFocalLength)
        static let sensorFormat = Column(CodingKeys.sensorFormat)
        static let fileSize = Column(CodingKeys.fileSize)
        static let isFavorite = Column(CodingKeys.isFavorite)
        static let exifStatus = Column(CodingKeys.exifStatus)
    }
}

/// Manual sensor-format mapping created by the user for cameras the
/// bundled database does not know.
struct CustomCameraMapping: Codable, Equatable, Identifiable, Sendable {
    var normalizedCameraModel: String
    var sensorFormat: String
    var cropFactor: Double?

    var id: String { normalizedCameraModel }
}

extension CustomCameraMapping: FetchableRecord, PersistableRecord {
    static let databaseTableName = "custom_camera_mappings"
}

/// Persistent state of the index pipeline (resume cursor, last run).
struct IndexState: Codable, Equatable, Sendable {
    var id: Int
    var cursorAssetId: String?
    var lastIndexedAt: Int?
    var lastFullIndexAt: Int?

    static let singletonId = 1

    static var initial: IndexState {
        IndexState(id: singletonId, cursorAssetId: nil, lastIndexedAt: nil, lastFullIndexAt: nil)
    }
}

extension IndexState: FetchableRecord, PersistableRecord {
    static let databaseTableName = "index_state"
}
