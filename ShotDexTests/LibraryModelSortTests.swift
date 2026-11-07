import Foundation
import Testing
@testable import ShotDex

/// FS-01.05 §5.1 — the Library model's side of the File Size orders.
@MainActor
struct LibraryModelSortTests {

    private func item(_ assetId: String, size: Int?, creation: Int?) -> LibraryGridItem {
        LibraryGridItem(
            assetId: assetId, creationDate: creation, mediaType: 1, originalFilename: nil,
            iso: nil, aperture: nil, shutterSpeedDisplay: nil, focalLength: nil, equivalentFocalLength: nil,
            width: nil, height: nil, fileSize: size)
    }

    // AC-S6 — a stored File Size order survives a relaunch instead of falling
    // back to the default the way an order the menu no longer offers does.
    @Test func restoresFileSize() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: SettingsKeys.librarySort)
        defer { defaults.set(saved, forKey: SettingsKeys.librarySort) }

        defaults.set(SortOption.fileSizeLargest.rawValue, forKey: SettingsKeys.librarySort)
        #expect(LibraryModel(dependencies: AppDependencies.preview()).sort == .fileSizeLargest)
        defaults.set(SortOption.fileSizeSmallest.rawValue, forKey: SettingsKeys.librarySort)
        #expect(LibraryModel(dependencies: AppDependencies.preview()).sort == .fileSizeSmallest)
    }

    // AC-S7 — iCloud-only placeholders have no size, so they go after every
    // indexed row, the unknown-size rows included, in both directions. Their
    // dates fall before, between and after the rows', so any date-ordered
    // merge would move one of them up among the rows.
    @Test func placeholdersLast() {
        let rows = [
            item("D", size: 210_000_000, creation: 1_766_534_400),
            item("A", size: 48_000_000, creation: 1_767_398_400),
            item("E", size: nil, creation: 1_781_049_600),
        ]
        let cloud = [
            item("Pold", size: nil, creation: 1_700_000_000),
            item("Pmid", size: nil, creation: 1_766_900_000),
            item("Pnew", size: nil, creation: 1_790_000_000),
            item("Pnil", size: nil, creation: nil),
        ]
        for sort in [SortOption.fileSizeLargest, .fileSizeSmallest] {
            let ids = LibraryModel.merging(cloud, into: rows, sort: sort).map(\.assetId)
            #expect(ids == ["D", "A", "E", "Pold", "Pmid", "Pnew", "Pnil"])
        }
        // Control: under a date order the same placeholders do interleave.
        let byDate = LibraryModel.merging(cloud, into: rows, sort: .dateTakenNewest).map(\.assetId)
        #expect(byDate.first == "Pnew")
    }
}
