import Foundation
import Testing
@testable import ShotDex

/// Pins the in-memory `SmartAlbumQuery.matches(_:)` (used by the importer to
/// filter not-yet-indexed files) to the same semantics `SmartAlbumSQLCompiler`
/// produces for indexed rows.
struct SmartAlbumQueryMatchingTests {
    /// Composes a realistic row the same way the index pipeline / importer do.
    private func row(
        filename: String? = nil,
        make: String? = nil,
        model: String? = nil,
        lens: String? = nil,
        iso: Int? = nil,
        fNumber: Double? = nil,
        shutter: Double? = nil,
        focal: Double? = nil,
        date: Date? = nil,
        favorite: Bool = false
    ) -> PhotoMetadata {
        let composer = MetadataComposer(sensorLookup: SensorLookup(records: [
            SensorCameraRecord(manufacturer: "Canon", model: "EOS R7", sensorFormat: "APS-C", cropFactor: 1.6, aliases: nil),
        ]))
        let asset = AssetInfo(
            assetId: filename ?? "asset",
            creationDate: date,
            modificationDate: date,
            mediaType: 1,
            width: nil, height: nil, fileSize: nil,
            latitude: nil, longitude: nil,
            isFavorite: favorite,
            originalFilename: filename
        )
        let exif = RawExif(
            make: make, model: model, lensModel: lens,
            iso: iso, fNumber: fNumber, exposureTimeSeconds: shutter,
            focalLength: focal, focalLengthIn35mm: nil
        )
        return composer.compose(asset: asset, exif: exif, exifStatus: .indexed)
    }

    private func query(_ mode: RuleMatchMode = .all, _ rules: SmartAlbumRule...) -> SmartAlbumQuery {
        SmartAlbumQuery(matchMode: mode, rules: rules)
    }

    // MARK: File type (the RAW-filtering core)

    @Test func fileTypeRawMatchesRawExtensionsOnly() {
        let raw = SmartAlbumRule(field: .fileType, op: .isExactly, text: PhotoFileType.raw.rawValue)
        #expect(query(.all, raw).matches(row(filename: "IMG_0001.CR2")))
        #expect(query(.all, raw).matches(row(filename: "IMG_0001.NEF")))
        #expect(!query(.all, raw).matches(row(filename: "IMG_0001.JPG")))
    }

    @Test func fileTypeJpegIsCaseInsensitive() {
        let jpeg = SmartAlbumRule(field: .fileType, op: .isExactly, text: PhotoFileType.jpeg.rawValue)
        #expect(query(.all, jpeg).matches(row(filename: "IMG_0001.JPG")))
        #expect(query(.all, jpeg).matches(row(filename: "img_0001.jpeg")))
        #expect(!query(.all, jpeg).matches(row(filename: "IMG_0001.CR2")))
    }

    @Test func fileTypeIsNotExcludesThatType() {
        let notRaw = SmartAlbumRule(field: .fileType, op: .isNot, text: PhotoFileType.raw.rawValue)
        #expect(notRaw.op == .isNot)
        #expect(query(.all, notRaw).matches(row(filename: "IMG.JPG")))
        #expect(!query(.all, notRaw).matches(row(filename: "IMG.ARW")))
    }

    // MARK: Text (normalized + raw columns, case-insensitive)

    @Test func cameraBodyContainsMatchesNormalizedModel() {
        let rule = SmartAlbumRule(field: .cameraBody, op: .contains, text: "R7")
        #expect(query(.all, rule).matches(row(make: "Canon", model: "Canon EOS R7")))
        #expect(!query(.all, rule).matches(row(make: "Canon", model: "Canon EOS R6")))
    }

    // MARK: Number (missing value never matches)

    @Test func isoGreaterThan() {
        let rule = SmartAlbumRule(field: .iso, op: .greaterThan, number: 800)
        #expect(query(.all, rule).matches(row(iso: 1600)))
        #expect(!query(.all, rule).matches(row(iso: 400)))
    }

    @Test func numberRuleFailsWhenValueMissing() {
        let rule = SmartAlbumRule(field: .iso, op: .greaterThan, number: 800)
        #expect(!query(.all, rule).matches(row(iso: nil)))
    }

    // MARK: Date

    @Test func dateAfterAndBefore() {
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let after = SmartAlbumRule(field: .dateTaken, op: .after, number: cutoff.timeIntervalSince1970)
        #expect(query(.all, after).matches(row(date: cutoff.addingTimeInterval(86_400))))
        #expect(!query(.all, after).matches(row(date: cutoff.addingTimeInterval(-86_400))))
    }

    // MARK: Match mode + empty

    @Test func matchAnyVsAll() {
        let isCanon = SmartAlbumRule(field: .cameraBrand, op: .contains, text: "Canon")
        let highISO = SmartAlbumRule(field: .iso, op: .greaterThan, number: 3200)
        let sample = row(make: "Canon", model: "Canon EOS R7", iso: 400)
        #expect(query(.any, isCanon, highISO).matches(sample))   // brand hits
        #expect(!query(.all, isCanon, highISO).matches(sample))  // ISO fails
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(SmartAlbumQuery(matchMode: .all, rules: []).matches(row(filename: "x.jpg")))
        // A half-typed (invalid) rule is skipped, leaving an empty query.
        let blank = SmartAlbumRule(field: .cameraBody, op: .contains, text: "")
        #expect(query(.all, blank).matches(row(filename: "x.jpg")))
    }
}

/// The extension-classifier the importer uses to bucket files (and hide RAW).
struct PhotoFileTypeClassifyTests {
    @Test func classifiesCommonExtensions() {
        #expect(PhotoFileType.classify(extension: "jpg") == .jpeg)
        #expect(PhotoFileType.classify(extension: "JPEG") == .jpeg)
        #expect(PhotoFileType.classify(extension: "heic") == .heic)
        #expect(PhotoFileType.classify(extension: "cr3") == .raw)
        #expect(PhotoFileType.classify(extension: "arw") == .raw)
        // .dng resolves to DNG (specific) rather than the generic RAW bag.
        #expect(PhotoFileType.classify(extension: "dng") == .dng)
        #expect(PhotoFileType.classify(extension: "mov") == nil)
        #expect(PhotoFileType.classify(extension: "") == nil)
    }

    @Test func rawFormatsFlaggedRaw() {
        #expect(PhotoFileType.raw.isRawFormat)
        #expect(PhotoFileType.dng.isRawFormat)
        #expect(!PhotoFileType.jpeg.isRawFormat)
        #expect(!PhotoFileType.heic.isRawFormat)
    }

    @Test func classifiesImageVsVideoVsOther() throws {
        let image = try #require(ImportCandidate.classify(url: URL(fileURLWithPath: "/dcim/IMG_0001.JPG")))
        #expect(image.kind == .image)
        #expect(image.fileType == .jpeg)

        let video = try #require(ImportCandidate.classify(url: URL(fileURLWithPath: "/dcim/CLIP.MOV")))
        #expect(video.kind == .video)
        #expect(video.fileType == nil)

        #expect(ImportCandidate.classify(url: URL(fileURLWithPath: "/dcim/notes.txt")) == nil)
    }
}
