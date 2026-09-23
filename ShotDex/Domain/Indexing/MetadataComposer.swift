import Foundation

/// Raw EXIF values as read from ImageIO, before any normalization.
struct RawExif: Equatable, Sendable {
    var make: String?
    var model: String?
    var lensMake: String?
    var lensModel: String?
    var iso: Int?
    var fNumber: Double?
    var exposureTimeSeconds: Double?
    var focalLength: Double?
    var focalLengthIn35mm: Double?
    /// ShotDex's panorama tag was found in the file (FS-14.02 §7). Not an EXIF
    /// value — it rides here because it comes from the same read of the same
    /// file, and nothing else opens that file.
    var hasPanoramaTag: Bool = false

    static let empty = RawExif()

    init(
        make: String? = nil,
        model: String? = nil,
        lensMake: String? = nil,
        lensModel: String? = nil,
        iso: Int? = nil,
        fNumber: Double? = nil,
        exposureTimeSeconds: Double? = nil,
        focalLength: Double? = nil,
        focalLengthIn35mm: Double? = nil,
        hasPanoramaTag: Bool = false
    ) {
        self.make = make
        self.model = model
        self.lensMake = lensMake
        self.lensModel = lensModel
        self.iso = iso
        self.fNumber = fNumber
        self.exposureTimeSeconds = exposureTimeSeconds
        self.focalLength = focalLength
        self.focalLengthIn35mm = focalLengthIn35mm
        self.hasPanoramaTag = hasPanoramaTag
    }

    /// Whether the read found **no EXIF**. The panorama tag is deliberately not
    /// part of this: it is not an exposure value, and a file that has only the
    /// tag still has nothing for the camera and lens columns — calling that
    /// "indexed" would leave a row claiming EXIF it does not have.
    var isEmpty: Bool {
        make == nil && model == nil && lensMake == nil && lensModel == nil
            && iso == nil && fNumber == nil && exposureTimeSeconds == nil
            && focalLength == nil && focalLengthIn35mm == nil
    }
}

/// Asset-level facts coming from PhotoKit (not EXIF).
struct AssetInfo: Equatable, Sendable {
    var assetId: String
    var creationDate: Date?
    var modificationDate: Date?
    var mediaType: Int
    /// Raw `PHAssetMediaSubtype` bitmask, straight off the asset.
    var mediaSubtypes: Int = 0
    /// The system's own pano flag, pulled out of `mediaSubtypes` by the caller
    /// so this type stays free of Photos. It is half the answer; the other half
    /// is `RawExif.hasPanoramaTag`, and `compose` joins them.
    var hasSystemPanoramaFlag: Bool = false
    var width: Int?
    var height: Int?
    var fileSize: Int?
    var latitude: Double?
    var longitude: Double?
    var isFavorite: Bool
    /// Original filename from `PHAssetResource`. Only populated in the EXIF
    /// pass (fast pass avoids the per-asset resource fetch); nil otherwise.
    var originalFilename: String? = nil
}

/// Combines PhotoKit asset info + raw EXIF + domain logic into one
/// `PhotoMetadata` row. Pure Swift.
struct MetadataComposer: Sendable {
    var sensorLookup: SensorLookup

    func compose(asset: AssetInfo, exif: RawExif, exifStatus: ExifStatus, now: Date = Date()) -> PhotoMetadata {
        let normalizedManufacturer = CameraNormalizer.normalizeManufacturer(exif.make)
        let normalizedModel = CameraNormalizer.normalizeModel(exif.model, manufacturer: exif.make)
        let normalizedLens = LensNormalizer.normalize(exif.lensModel)

        let sensor = sensorLookup.lookup(normalizedModel: normalizedModel)

        let calculated = EquivalentFocalLength.calculate(
            actualFocalLength: exif.focalLength,
            cropFactor: sensor.cropFactor
        )
        let equivalent = EquivalentFocalLength.resolve(
            exif35mm: exif.focalLengthIn35mm,
            actualFocalLength: exif.focalLength,
            cropFactor: sensor.cropFactor
        )

        return PhotoMetadata(
            assetId: asset.assetId,
            creationDate: asset.creationDate.map { Int($0.timeIntervalSince1970) },
            modificationDate: asset.modificationDate.map { Int($0.timeIntervalSince1970) },
            mediaType: asset.mediaType,
            mediaSubtypes: asset.mediaSubtypes,
            // Either source makes it one (FS-14 §7): Camera's own panoramas
            // carry the system flag, and the ones ShotDex stitched carry the
            // tag in the file.
            isPanorama: asset.hasSystemPanoramaFlag || exif.hasPanoramaTag,
            cameraManufacturer: exif.make,
            cameraModel: exif.model,
            normalizedCameraModel: normalizedModel,
            normalizedCameraManufacturer: normalizedManufacturer,
            lensManufacturer: exif.lensMake,
            lensModel: exif.lensModel,
            normalizedLensModel: normalizedLens,
            originalFilename: asset.originalFilename,
            iso: exif.iso,
            aperture: exif.fNumber,
            shutterSpeedSeconds: exif.exposureTimeSeconds,
            shutterSpeedDisplay: exif.exposureTimeSeconds.flatMap(MetadataFormatter.shutterSpeed),
            focalLength: exif.focalLength,
            focalLengthIn35mm: exif.focalLengthIn35mm,
            calculatedEquivalentFocalLength: calculated,
            equivalentFocalLength: equivalent,
            sensorFormat: normalizedModel == nil ? nil : sensor.sensorFormat.rawValue,
            cropFactor: sensor.cropFactor,
            width: asset.width,
            height: asset.height,
            fileSize: asset.fileSize,
            latitude: asset.latitude,
            longitude: asset.longitude,
            isFavorite: asset.isFavorite,
            indexedAt: Int(now.timeIntervalSince1970),
            exifStatus: (exifStatus == .indexed && exif.isEmpty ? ExifStatus.noExif : exifStatus).rawValue
        )
    }
}
