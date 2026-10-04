import CoreGraphics
import Photos
import Testing
@testable import ShotDex

/// The Media panel's library (FS-12.09): what it fetches, how far ahead it
/// warms thumbnails, and the grid's shape. PhotoKit itself is not reachable
/// from unit tests; the fetch it is asked for and the windows it is given
/// are.
@MainActor
struct VideoMediaLibraryTests {
    /// AC-11 (fetch half): Recents is every photo and video, newest first,
    /// with no fetch limit — nothing stops at 400 and nothing sends the user
    /// to a "Browse All Photos…" row.
    @Test func recentsIsTheWholeFetchNoCap() {
        let options = VideoMediaLibrary.recentsOptions()
        #expect(options.fetchLimit == 0)
        #expect(options.predicate == PhotoLibraryService.browsableMediaPredicate)
        #expect(options.sortDescriptors?.map(\.key) == ["creationDate"])
        #expect(options.sortDescriptors?.first?.ascending == false)
        #expect(VideoMediaLibrary.albumOptions().fetchLimit == 0)
        #expect(VideoMediaLibrary.searchOptions().fetchLimit == 0)
    }

    /// FS-12.09 §7: at most two screens of grid are warmed beyond what is on
    /// screen — one above, one below — and never past either end.
    @Test func prefetchWindowIsTwoScreens() {
        // Phone: 4 columns of 99 + 2, a 300pt viewport → 3 rows = 12 items.
        let perScreen = VideoMediaPrefetch.itemsPerScreen(columns: 4, cellHeight: 101, viewportHeight: 300)
        #expect(perScreen == 12)
        let visible = 400..<412
        let window = VideoMediaPrefetch.window(visible: visible, itemsPerScreen: perScreen, count: 55_000)
        #expect(window == 388..<424)
        #expect(window.count - visible.count <= 2 * perScreen)

        // At the top and the bottom of the library the window stops at the ends.
        #expect(VideoMediaPrefetch.window(visible: 0..<12, itemsPerScreen: 12, count: 55_000) == 0..<24)
        #expect(VideoMediaPrefetch.window(visible: 54_990..<55_000, itemsPerScreen: 12, count: 55_000) == 54_978..<55_000)
        #expect(VideoMediaPrefetch.window(visible: 0..<0, itemsPerScreen: 12, count: 0).isEmpty)
    }

    /// A moved window starts and stops caching only what entered or left it.
    @Test func prefetchMovesByTheDifferenceOnly() {
        #expect(VideoMediaPrefetch.subtract(10..<20, from: 0..<30) == [0..<10, 20..<30])
        #expect(VideoMediaPrefetch.subtract(12..<36, from: 0..<24) == [0..<12])
        #expect(VideoMediaPrefetch.subtract(0..<24, from: 12..<36) == [24..<36])
        #expect(VideoMediaPrefetch.subtract(50..<60, from: 0..<24) == [0..<24])
        #expect(VideoMediaPrefetch.subtract(0..<24, from: 0..<24).isEmpty)
    }

    /// FS-12.09 §3: square cells, four columns of 99 with 2pt gaps across a
    /// 402pt phone, edge to edge; a narrower phone keeps four columns.
    @Test func phoneGridIsFourColumnsOf99() {
        let phone = VideoMediaGridMetrics.for(.phone)
        #expect(phone.columns == 4)
        #expect(phone.cellSide(width: 402) == 99)
        #expect(phone.cellSide(width: 402) * 4 + phone.gap * 3 + phone.inset * 2 == 402)
        #expect(phone.cellSide(width: 375) == 92)
    }
}

extension VideoMediaLibraryTests {
    /// AC-19 (fetch half): an album's grid is that album's own items,
    /// photos and videos, newest first and uncapped — the same fetch shape
    /// as Recents, so it carries the same used-marks.
    @Test func albumGridIsTheAlbumFetch() {
        let album = VideoMediaLibrary.albumOptions()
        let recents = VideoMediaLibrary.recentsOptions()
        #expect(album.fetchLimit == 0)
        #expect(album.predicate == recents.predicate)
        #expect(album.sortDescriptors == recents.sortDescriptors)
    }
}

extension VideoMediaLibraryTests {
    /// AC-9 (words): the limited row counts what was granted, in the
    /// Library's one label for it, singular for one.
    @Test func limitedRowCountsGrantedItems() {
        #expect(VideoStudioCopy.limitedAccess(12) == "ShotDex can see the 12 items you chose.")
        #expect(VideoStudioCopy.limitedAccess(1) == "ShotDex can see the 1 item you chose.")
        #expect(VideoStudioCopy.manageAccess == "Manage Access…")
        #expect(VideoStudioCopy.itemsInThisVideo(1) == "1 item in this video")
    }
}

extension VideoMediaLibraryTests {
    /// AC-12: twenty photos taken at 85mm among others → "85mm" finds
    /// exactly those twenty, through the Library's own query language.
    @Test func searchUsesTheLibraryQueryLanguage() async throws {
        let dependencies = AppDependencies.preview()
        func row(_ id: String, focal: Double) -> PhotoMetadata {
            PhotoMetadata(
                assetId: id, creationDate: 1_700_000_000, modificationDate: 1_700_000_000, mediaType: 1,
                cameraManufacturer: "Canon", cameraModel: "EOS R6", normalizedCameraModel: "EOS R6",
                normalizedCameraManufacturer: "Canon", lensManufacturer: nil, lensModel: nil,
                normalizedLensModel: nil, originalFilename: "\(id).JPG", iso: 400, aperture: 2,
                shutterSpeedSeconds: 0.005, shutterSpeedDisplay: "1/200", focalLength: focal,
                focalLengthIn35mm: nil, calculatedEquivalentFocalLength: nil, equivalentFocalLength: focal,
                sensorFormat: nil, cropFactor: nil, width: 6000, height: 4000, fileSize: nil,
                latitude: nil, longitude: nil, isFavorite: false, indexedAt: 1_700_000_000,
                exifStatus: ExifStatus.indexed.rawValue
            )
        }
        for index in 0..<20 { try dependencies.metadataStore.upsert(row("tele-\(index)", focal: 85)) }
        for index in 0..<12 { try dependencies.metadataStore.upsert(row("wide-\(index)", focal: 35)) }
        let ids = await VideoMediaLibrary.searchIDs(
            "85mm", service: dependencies.searchService, queries: dependencies.libraryQueries
        )
        #expect(ids.count == 20)
        #expect(Set(ids) == Set((0..<20).map { "tele-\($0)" }))
    }
}
