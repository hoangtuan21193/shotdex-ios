import Foundation
import Testing
@testable import ShotDex

/// FS-18 AC-35 (02 §5): Save as Smart Album… and Advanced Filter… start from
/// `SmartAlbumQuery.migrating(criteria)`. For every quick-filter field the
/// album must hold exactly the photos the filter shows — or the condition
/// is named by `migrationGaps` and the buttons stay off.
@MainActor
struct FilterCriteriaMigrationTests {

    /// 24 photos that differ on every field the filter reads.
    private func library() async throws -> AppDatabase {
        let database = try AppDatabase.makeEmpty()
        let cameras: [(brand: String, body: String, lens: String)] = [
            ("Sony", "A7 IV", "FE 85mm F1.8"), ("Canon", "EOS R6 Mark II", "RF 35mm F1.8"), ("Fujifilm", "X-T5", "XF 56mm F1.2"),
        ]
        var rows: [PhotoMetadata] = []
        for n in 0..<24 {
            let camera = cameras[n % 3]
            let created = Int(CaptureMonth(year: 2026, month: n % 2 == 0 ? 3 : 4).anchorDate().timeIntervalSince1970) + n * 60
            rows.append(PhotoMetadata(
                assetId: "p\(n)", creationDate: created, modificationDate: created,
                mediaType: (n % 5 == 0 ? MediaKind.video : .photo).storedValue,
                cameraManufacturer: camera.brand, cameraModel: camera.body, normalizedCameraModel: camera.body,
                normalizedCameraManufacturer: camera.brand, lensManufacturer: nil, lensModel: camera.lens,
                normalizedLensModel: camera.lens, originalFilename: "IMG_\(n).JPG",
                iso: [100, 400, 1600, 3200, 6400][n % 5], aperture: [1.2, 1.8, 2.8, 4, 8][n % 5],
                shutterSpeedSeconds: [0.002, 0.004, 0.008, 0.033][n % 4], shutterSpeedDisplay: nil,
                focalLength: [24, 35, 56, 85][n % 4], focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil,
                equivalentFocalLength: [36, 52, 85, 128][n % 4],
                sensorFormat: (n % 3 == 2 ? SensorFormat.apsC : .fullFrame).rawValue, cropFactor: nil,
                width: 6000, height: 4000, fileSize: 1_000_000, latitude: nil, longitude: nil,
                isFavorite: n % 4 == 1, indexedAt: 1, exifStatus: ExifStatus.indexed.rawValue
            ))
        }
        try MetadataStore(database: database).saveBatch(rows, cursorAssetId: nil)
        let marks = PhotoMarks(store: PhotoMarksStore(database: database))
        for n in 0..<24 where n % 6 != 0 { await marks.setRating(n % 6, ids: ["p\(n)"]) }
        await marks.setFlag(.pick, ids: ["p1", "p4", "p7", "p10"])
        await marks.setFlag(.reject, ids: ["p2", "p5"])
        try await database.writer.write { db in
            for n in 0..<24 where n % 3 != 1 {
                try db.execute(sql: "INSERT INTO original_presence (photoKitId, state, checkedAt) VALUES (?, ?, 1)",
                               arguments: ["p\(n)", (n % 3 == 0 ? OriginalPresence.onDevice : .iCloudOnly).rawValue])
            }
        }
        return database
    }

    /// One case per field; ranges with both bounds (a one-sided bound
    /// saves as a strict > / <, the rule's only one-sided operators).
    private static var cases: [(String, FilterCriteria)] {
        func make(_ edit: (inout FilterCriteria) -> Void) -> FilterCriteria { var c = FilterCriteria(); edit(&c); return c }
        return [
            ("brand", make { $0.cameraBrands = ["Canon"] }),
            ("body", make { $0.cameraBodies = ["X-T5"] }),
            ("lens", make { $0.lenses = ["FE 85mm F1.8"] }),
            ("sensor", make { $0.sensorFormats = [.apsC] }),
            ("brandTerm", make { $0.cameraBrandTerms = ["fuji"] }),
            ("bodyTerm", make { $0.cameraBodyTerms = ["R6"] }),
            ("lensTerm", make { $0.lensTerms = ["85mm"] }),
            ("iso", make { $0.isoRange = NumericRangeFilter(lowerBound: 400, upperBound: 3200) }),
            ("shutter", make { $0.shutterRange = NumericRangeFilter(lowerBound: 0.004, upperBound: 0.008) }),
            ("aperture", make { $0.apertureRange = NumericRangeFilter(lowerBound: 1.2, upperBound: 2.8) }),
            ("focal", make { $0.focalRange = NumericRangeFilter(lowerBound: 35, upperBound: 56) }),
            ("focalEq", make { $0.focalRange = NumericRangeFilter(lowerBound: 50, upperBound: 90); $0.focalLengthMode = .equivalent }),
            ("photos", make { $0.mediaKinds = [.photo] }),
            ("videos", make { $0.mediaKinds = [.video] }),
            ("favorites", make { $0.favoritesOnly = true }),
            ("original", make { $0.originalOnDeviceOnly = true }),
            ("rating3", make { $0.ratingFilter = .atLeast(3) }),
            ("unrated", make { $0.ratingFilter = .unrated }),
            ("picks", make { $0.flags = [.picks] }),
            ("rejected", make { $0.flags = [.rejected] }),
            ("unflagged", make { $0.flags = [.unflagged] }),
            ("picksOrRejected", make { $0.flags = [.picks, .rejected] }),
            ("picksOrUnflagged", make { $0.flags = [.picks, .unflagged] }),
            ("allFlags", make { $0.flags = Set(PhotoFlagFilter.allCases) }),
            ("month", make { $0.captureMonth = CaptureMonth(year: 2026, month: 3) }),
            ("search", make { $0.searchText = "Sony ISO 400 f/1.8 full frame" }),
            ("everything", make {
                $0.cameraBodies = ["A7 IV"]; $0.isoRange = NumericRangeFilter(lowerBound: 100, upperBound: 6400)
                $0.mediaKinds = [.photo]; $0.ratingFilter = .atLeast(1); $0.flags = [.picks, .unflagged]
                $0.originalOnDeviceOnly = true; $0.captureMonth = CaptureMonth(year: 2026, month: 4)
            }),
        ]
    }

    @Test func everyQuickFilterSavesAsTheSamePhotos() async throws {
        let database = try await library()
        let queries = LibraryQueries(database: database)
        for (name, criteria) in Self.cases {
            #expect(SmartAlbumQuery.migrationGaps(criteria).isEmpty, "\(name) has a gap")
            let quick = try queries.count(matching: criteria)
            let album = try await queries.count(matching: SmartAlbumQuery.migrating(criteria))
            #expect(quick == album, "\(name): filter \(quick), album \(album)")
            // A case that matches everything or nothing proves little.
            if name != "allFlags" { #expect(quick > 0 && quick < 24, "\(name) matches \(quick)") }
        }
    }

    /// What has no rule is named, so the buttons can say why they are off.
    @Test func conditionsWithoutARuleAreNamed() {
        // One capture kind saves as *Photo is …* (FS-06.08 §3c); two OR in the
        // filter, and Unsupported RAW is a verdict with no rule.
        var subtypes = FilterCriteria()
        subtypes.mediaSubtypes = [.livePhoto, .hdr]
        #expect(SmartAlbumQuery.migrationGaps(subtypes) == ["Capture Kind"])
        subtypes.mediaSubtypes = [.unsupportedRAW]
        #expect(SmartAlbumQuery.migrationGaps(subtypes) == ["Capture Kind"])
        subtypes.mediaSubtypes = [.livePhoto]
        #expect(SmartAlbumQuery.migrationGaps(subtypes).isEmpty)
        var twoCameras = FilterCriteria()
        twoCameras.cameraBodies = ["A7 IV", "X-T5"]
        #expect(SmartAlbumQuery.migrationGaps(twoCameras) == ["several cameras"])
        var focalSearch = FilterCriteria()
        focalSearch.searchText = "85mm"
        #expect(SmartAlbumQuery.migrationGaps(focalSearch).count == 1)
        #expect(SmartAlbumQuery.migrationGaps(FilterCriteria()).isEmpty)
    }
}
