import Foundation
import Testing
@testable import ShotDex

/// FS-06.06 §14.7 (after Immich): Compare lists only the facts that differ
/// between A and B, first five, then *Show N more*.
struct PhotoDifferenceTests {
    private let when = Date(timeIntervalSince1970: 1_772_373_731) // 2026-03-01 14:02:11 UTC

    private func facts(
        size: Int = 5_100_000, width: Int = 4032, height: Int = 3024, format: String = "HEIC",
        place: String? = "Hội An", hasLocation: Bool = true, albums: [String] = ["Client"]
    ) -> PhotoFacts {
        PhotoFacts(date: when, fileSize: size, width: width, height: height, format: format,
                   camera: "iPhone 17 Pro", lens: "24 mm f/1.78", aperture: 1.78, shutterSeconds: 1.0 / 120,
                   iso: 64, focalLength: 6.9, hasLocation: hasLocation, latitude: hasLocation ? 15.877 : nil,
                   longitude: hasLocation ? 108.326 : nil, placeName: place, albums: albums, rating: 0,
                   keywords: [], isEdited: false, source: nil)
    }

    /// AC-I13: five rows, in spec order; the shared date is not listed.
    @Test func onlyDifferingFieldsAreListed() {
        let a = facts()
        let b = facts(size: 1_200_000, width: 1600, height: 1200, format: "JPEG", place: nil, hasLocation: false, albums: [])
        let rows = PhotoDifference.rows(a, b)
        #expect(rows.map(\.field) == [.fileSize, .dimensions, .format, .location, .albums])
        #expect(rows.first { $0.field == .dimensions }?.b == "1600 × 1200")
        #expect(rows.first { $0.field == .location }?.b == String(localized: "None"))
        #expect(PhotoDifference.visible(rows, expanded: false).count == 5)
        #expect(PhotoDifference.hiddenCount(rows) == 0)
    }

    /// AC-I14: eight differing fields → five, then *Show 3 more*.
    @Test func firstFiveThenShowMore() {
        let a = facts()
        var b = facts(size: 1_200_000, width: 1600, height: 1200, format: "JPEG", place: nil, hasLocation: false, albums: [])
        b.rating = 3
        b.keywords = ["Kodak"]
        b.source = "WhatsApp"
        let rows = PhotoDifference.rows(a, b)
        #expect(rows.count == 8)
        #expect(PhotoDifference.visible(rows, expanded: false).count == 5)
        #expect(PhotoDifference.hiddenCount(rows) == 3)
        #expect(PhotoDifference.visible(rows, expanded: true).count == 8)
    }

    /// Values compare after rounding, like Immich: the same instant to the
    /// second, f/1.78 vs f/1.8, a coordinate 4 decimals in — no row.
    @Test func roundingKeepsNearEqualValuesOut() {
        let a = facts()
        var b = facts()
        b.date = when.addingTimeInterval(0.4)
        b.aperture = 1.8
        b.latitude = 15.87704
        #expect(PhotoDifference.rows(a, b).isEmpty)
        b.date = when.addingTimeInterval(2)
        #expect(PhotoDifference.rows(a, b).map(\.field) == [.date])
    }

    /// Values that read the same are the same: bytes inside one MB step, an
    /// out-of-range rating, a blank shutter; a bad shutter never leaves a
    /// dangling separator.
    @Test func sameReadingIsNoRow() {
        let a = facts()
        var b = facts(size: 5_100_400)
        #expect(PhotoDifference.rows(a, b).isEmpty)
        b.rating = 7
        var c = facts(); c.rating = 5
        #expect(PhotoDifference.rows(c, b).isEmpty)
        b.rating = -1
        #expect(PhotoDifference.display(.rating, b) == String(localized: "None"))
        var d = facts(); d.shutterSeconds = 0
        #expect(!PhotoDifference.display(.settings, d).contains(" ·  · "))
        #expect(!PhotoDifference.display(.settings, d).hasSuffix("· "))
    }

    /// Albums and keywords compare as sets, order and case of keywords aside.
    @Test func listsCompareAsSets() {
        var a = facts(albums: ["Trip", "Client"])
        a.keywords = ["Kodak", "film"]
        var b = facts(albums: ["Client", "Trip"])
        b.keywords = ["Film", "kodak"]
        #expect(PhotoDifference.rows(a, b).isEmpty)
        var dup = facts(albums: ["A", "A"])
        dup.keywords = ["Kodak", "kodak"]
        #expect(PhotoDifference.rows(dup, facts(albums: ["A"])).map(\.field) == [.keywords])
    }
}

/// What Compare reads for one photo (FS-06.06 §14.7).
struct PhotoFactsLoaderTests {
    @Test func factsComeFromTheIndexRow() {
        var row = PhotoMetadata(
            assetId: "a", creationDate: 1_772_373_731, modificationDate: 1, mediaType: MediaKind.photo.storedValue,
            cameraManufacturer: "Apple", cameraModel: "iPhone 17 Pro", normalizedCameraModel: "iPhone 17 Pro",
            normalizedCameraManufacturer: "Apple", lensManufacturer: nil, lensModel: "back camera",
            normalizedLensModel: nil, originalFilename: "IMG_0001.jpg", iso: 64, aperture: 1.78,
            shutterSpeedSeconds: 1.0 / 120, shutterSpeedDisplay: "1/120", focalLength: 6.9, focalLengthIn35mm: 24,
            calculatedEquivalentFocalLength: nil, equivalentFocalLength: 24, sensorFormat: nil, cropFactor: nil,
            width: 4032, height: 3024, fileSize: 5_100_000, latitude: 15.877, longitude: 108.326, isFavorite: false,
            indexedAt: 1, exifStatus: ExifStatus.indexed.rawValue)
        row.hasAdjustments = true
        let facts = PhotoFactsLoader.facts(metadata: row, place: ResolvedPlace(locality: "Hội An"),
                                           keywords: ["Kodak"], albums: ["Client"], rating: 4)
        #expect(facts.format == "JPEG")
        #expect(facts.placeName == "Hội An")
        #expect(facts.hasLocation)
        #expect(facts.lens == "back camera")
        #expect(facts.isEdited)
        #expect(facts.rating == 4)
        #expect(facts.albums == ["Client"])
        #expect(PhotoFactsLoader.format(of: nil) == nil)
        #expect(PhotoFactsLoader.format(of: "DSC0001.ARW") == "ARW")
    }
}
