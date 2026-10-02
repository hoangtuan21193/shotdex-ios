import Foundation
import os
@testable import ShotDex

/// Index rows and a scripted decoder for the FS-03.04b tests.
enum RAWVerdictFixtures {
    /// A photo as the index has it: its file's name and the camera EXIF
    /// names, normalized the way `MetadataComposer` does.
    static func row(_ id: String, file: String, make: String?, model: String?, date: Int = 1_700_000_000) -> PhotoMetadata {
        PhotoMetadata(
            assetId: id,
            creationDate: date,
            modificationDate: date,
            mediaType: 1,
            cameraManufacturer: make,
            cameraModel: model,
            normalizedCameraModel: CameraNormalizer.normalizeModel(model, manufacturer: make),
            normalizedCameraManufacturer: CameraNormalizer.normalizeManufacturer(make),
            lensManufacturer: nil,
            lensModel: nil,
            normalizedLensModel: nil,
            originalFilename: file,
            iso: 200,
            aperture: 2.8,
            shutterSpeedSeconds: 0.005,
            shutterSpeedDisplay: "1/200",
            focalLength: 50,
            focalLengthIn35mm: nil,
            calculatedEquivalentFocalLength: nil,
            equivalentFocalLength: 50,
            sensorFormat: nil,
            cropFactor: nil,
            width: 6000,
            height: 4000,
            fileSize: nil,
            latitude: nil,
            longitude: nil,
            isFavorite: false,
            indexedAt: date,
            exifStatus: ExifStatus.indexed.rawValue
        )
    }

    /// `count` rows of one camera, ids `<prefix>1…`, files `<prefix>1.<ext>`.
    static func rows(_ prefix: String, _ count: Int, ext: String, make: String?, model: String?) -> [PhotoMetadata] {
        (1...count).map { row("\(prefix)\($0)", file: "\(prefix)\($0).\(ext)", make: make, model: model, date: 1_700_000_000 + $0) }
    }

    static func database(_ rows: [PhotoMetadata]) throws -> AppDatabase {
        let database = try AppDatabase.makeEmpty()
        let store = MetadataStore(database: database)
        for row in rows { try store.upsert(row) }
        return database
    }

    static let release = OSRelease(build: "24A100", version: "27.0")
}

/// A decoder whose list and files the test sets: `local` ids are on the
/// device and decode as `decodes` says; every other id is only in iCloud.
final class FakeRAWProbe: RAWDecoderProbing, @unchecked Sendable {
    let models: [String]
    let local: Set<String>
    let decodes: @Sendable (String) -> Bool
    private let lock = OSAllocatedUnfairLock(initialState: [String]())
    /// Every id the pass asked about, in order — local or not.
    var asked: [String] { lock.withLock { $0 } }

    init(models: [String] = [], local: Set<String> = [], decodes: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.models = models
        self.local = local
        self.decodes = decodes
    }

    func supportedCameraModels() -> [String] { models }

    func localFileDecodes(assetId: String) async -> Bool? {
        lock.withLock { $0.append(assetId) }
        guard local.contains(assetId) else { return nil }
        return decodes(assetId)
    }
}
