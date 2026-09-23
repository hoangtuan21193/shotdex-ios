import Foundation
import Testing
@testable import ShotDex

struct MetadataComposerTests {
    private var composer: MetadataComposer {
        MetadataComposer(sensorLookup: SensorLookup(records: [
            SensorCameraRecord(manufacturer: "Canon", model: "EOS R7", sensorFormat: "APS-C", cropFactor: 1.6, aliases: nil),
        ]))
    }

    private var assetInfo: AssetInfo {
        AssetInfo(
            assetId: "asset-1",
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            modificationDate: Date(timeIntervalSince1970: 1_700_000_100),
            mediaType: 1,
            width: 6960,
            height: 4640,
            fileSize: 12_000_000,
            latitude: 35.68,
            longitude: 139.76,
            isFavorite: true
        )
    }

    @Test func composesFullRecord() {
        let exif = RawExif(
            make: "Canon",
            model: "Canon EOS R7",
            lensModel: "RF50mm F1.8 STM",
            iso: 400,
            fNumber: 1.8,
            exposureTimeSeconds: 1.0 / 500.0,
            focalLength: 50,
            focalLengthIn35mm: nil
        )
        let record = composer.compose(asset: assetInfo, exif: exif, exifStatus: .indexed)

        #expect(record.assetId == "asset-1")
        #expect(record.normalizedCameraManufacturer == "Canon")
        #expect(record.normalizedCameraModel == "EOS R7")
        #expect(record.normalizedLensModel == "RF 50mm F1.8 STM")
        #expect(record.sensorFormat == "APS-C")
        #expect(record.cropFactor == 1.6)
        #expect(record.calculatedEquivalentFocalLength == 80)
        #expect(record.equivalentFocalLength == 80)
        #expect(record.shutterSpeedDisplay == "1/500s")
        #expect(record.isFavorite)
        #expect(record.resolvedExifStatus == .indexed)
        #expect(record.megapixels.map { abs($0 - 32.29) < 0.1 } == true)
    }

    @Test func exif35mmWinsOverCalculation() {
        let exif = RawExif(make: "Canon", model: "EOS R7", focalLength: 50, focalLengthIn35mm: 75)
        let record = composer.compose(asset: assetInfo, exif: exif, exifStatus: .indexed)
        #expect(record.equivalentFocalLength == 75)
        #expect(record.calculatedEquivalentFocalLength == 80)
    }

    @Test func emptyExifBecomesNoExif() {
        let record = composer.compose(asset: assetInfo, exif: .empty, exifStatus: .indexed)
        #expect(record.resolvedExifStatus == .noExif)
        #expect(record.sensorFormat == nil)
        #expect(record.equivalentFocalLength == nil)
    }

    @Test func pendingICloudStatusPreserved() {
        let record = composer.compose(asset: assetInfo, exif: .empty, exifStatus: .pendingICloud)
        #expect(record.resolvedExifStatus == .pendingICloud)
    }

    @Test func pendingReadStatusPreserved() {
        // Fast-pass rows: empty EXIF must stay pendingRead, not collapse to noExif.
        let record = composer.compose(asset: assetInfo, exif: .empty, exifStatus: .pendingRead)
        #expect(record.resolvedExifStatus == .pendingRead)
    }

    @Test func unknownCameraGetsUnknownFormat() {
        let exif = RawExif(make: "Mystery", model: "Cam 3000", focalLength: 50)
        let record = composer.compose(asset: assetInfo, exif: exif, exifStatus: .indexed)
        #expect(record.sensorFormat == SensorFormat.unknown.rawValue)
        #expect(record.cropFactor == nil)
        #expect(record.equivalentFocalLength == nil)
    }

    /// FS-14: the composer does not decide what a panorama is — it is handed
    /// the answer, because resolving it needs both PhotoKit and the file, and
    /// this layer knows neither.
    @Test func eitherPanoramaSourceIsEnough() {
        var systemFlagged = assetInfo
        systemFlagged.hasSystemPanoramaFlag = true
        let tagged = RawExif(make: "Canon", hasPanoramaTag: true)

        #expect(composer.compose(asset: systemFlagged, exif: .empty, exifStatus: .indexed).isPanorama == true)
        #expect(composer.compose(asset: assetInfo, exif: tagged, exifStatus: .indexed).isPanorama == true)
        #expect(composer.compose(asset: assetInfo, exif: .empty, exifStatus: .indexed).isPanorama == false)
    }

    /// The tag says what the picture is, not what the exposure was. A file with
    /// the tag and no EXIF still has nothing to put in the camera columns, so
    /// it must not come out as `indexed`.
    @Test func panoramaTagAloneIsStillNoExif() {
        let record = composer.compose(
            asset: assetInfo, exif: RawExif(hasPanoramaTag: true), exifStatus: .indexed
        )
        #expect(record.resolvedExifStatus == .noExif)
        #expect(record.isPanorama == true)
    }
}
