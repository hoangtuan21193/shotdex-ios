import Foundation
import Photos
import SwiftUI

/// Navigation destination value for the On This Day screen.
struct OnThisDayDestination: Hashable {}

/// One year's group of photos: a contiguous index range into the flat
/// `photos` array, so a tile tap maps straight to the pager index.
struct OnThisDayYearSection: Identifiable {
    let year: Int
    let range: Range<Int>
    var id: Int { year }
}

/// Photos taken on one calendar date (month/day) across all previous years.
/// Loads everything at once — per-day volume is small — and supports
/// deleting assets from the library.
@MainActor
@Observable
final class OnThisDayController: PhotoBrowsingSource {
    private let metadataDAO: MetadataDAO
    private let database: AppDatabase
    private let photoLibrary: PhotoLibraryService
    private let indexPipeline: IndexPipeline
    private let calendar = Calendar.current

    /// The date whose month/day is matched. Changing it reloads.
    var selectedDate: Date {
        didSet { reload() }
    }

    private(set) var photos: [PhotoMetadata] = []
    private(set) var assetsById: [String: PHAsset] = [:]
    private(set) var sections: [OnThisDayYearSection] = []
    private(set) var isLoading = false

    /// Bumped when the content is *replaced* (date change, delete) so the grid
    /// reloads and re-anchors. A date change can land a same-count array, which
    /// the grid's count check alone would miss.
    private(set) var contentGeneration = 0
    /// Bumped when the same ordered list gains fresher per-tile data (favorite
    /// toggle, a viewer download that indexed a row) — visible cells
    /// reconfigure in place and the scroll position is kept.
    private(set) var contentRefreshGeneration = 0

    /// Year groups in the shared grid's section contract.
    var gridSections: [PhotoGridCustomSection] {
        let currentYear = calendar.component(.year, from: .now)
        return sections.map { section in
            let yearsAgo = currentYear - section.year
            let suffix = yearsAgo == 1 ? "1 year ago" : "\(yearsAgo) years ago"
            return PhotoGridCustomSection(
                range: section.range, title: "\(section.year) · \(suffix)"
            )
        }
    }

    /// Stale-result guard: a date change mid-load bumps this so the older
    /// load's result is dropped instead of overwriting the newer one.
    private var reloadGeneration = 0

    /// Assets and joined metadata fetched off the main thread; the compound
    /// OR-predicate fetch scans the whole library and is too slow for main.
    private struct Snapshot: @unchecked Sendable {
        var photos: [PhotoMetadata]
        var assetsById: [String: PHAsset]
    }

    init(dependencies: AppDependencies, selectedDate: Date = .now) {
        self.metadataDAO = dependencies.metadataDAO
        self.database = dependencies.database
        self.photoLibrary = dependencies.photoLibrary
        self.indexPipeline = dependencies.indexPipeline
        self.selectedDate = selectedDate
    }

    // MARK: Fetching

    /// Assets matching the month/day of `date` in previous years, newest
    /// first. Shared with the Albums-tab card summary.
    nonisolated static func fetchAssets(
        for date: Date,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let imagePredicate = PhotoLibraryService.browsableMediaPredicate

        // Probe the oldest asset so we don't build windows for empty years.
        let probeOptions = PHFetchOptions()
        probeOptions.predicate = imagePredicate
        probeOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        probeOptions.fetchLimit = 1
        let earliestDate = PHAsset.fetchAssets(with: probeOptions).firstObject?.creationDate
        let earliestYear = calendar.component(.year, from: earliestDate ?? now)

        let windows = OnThisDayWindows.windows(
            for: date, earliestYear: earliestYear, calendar: calendar, now: now
        )
        guard !windows.isEmpty else {
            // No previous years to match — a predicate that matches nothing.
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                imagePredicate,
                NSPredicate(format: "creationDate < %@", Date.distantPast as NSDate),
            ])
            return PHAsset.fetchAssets(with: options)
        }

        let windowPredicates = windows.map {
            NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                $0.start as NSDate, $0.end as NSDate
            )
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            imagePredicate,
            NSCompoundPredicate(orPredicateWithSubpredicates: windowPredicates),
        ])
        return PHAsset.fetchAssets(with: options)
    }

    func reload() {
        isLoading = true
        reloadGeneration += 1
        let generation = reloadGeneration
        let date = selectedDate
        let calendar = calendar
        let database = database
        Task {
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.loadSnapshot(for: date, calendar: calendar, database: database)
            }.value
            guard generation == reloadGeneration else { return }
            photos = snapshot.photos
            assetsById = snapshot.assetsById
            rebuildSections()
            contentGeneration &+= 1
            isLoading = false
        }
    }

    private nonisolated static func loadSnapshot(
        for date: Date,
        calendar: Calendar,
        database: AppDatabase
    ) -> Snapshot {
        let fetchResult = fetchAssets(for: date, calendar: calendar)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        let ids = assets.map(\.localIdentifier)
        let indexed = (try? fetchMetadata(ids: ids, database: database)) ?? [:]

        var newPhotos: [PhotoMetadata] = []
        var newAssetsById: [String: PHAsset] = [:]
        newPhotos.reserveCapacity(assets.count)
        for asset in assets {
            newAssetsById[asset.localIdentifier] = asset
            newPhotos.append(indexed[asset.localIdentifier] ?? .placeholder(for: asset))
        }
        return Snapshot(photos: newPhotos, assetsById: newAssetsById)
    }

    private func rebuildSections() {
        var result: [OnThisDayYearSection] = []
        var sectionStart = 0
        var currentYear: Int?
        for (index, photo) in photos.enumerated() {
            let year = photo.creationDateValue.map { calendar.component(.year, from: $0) } ?? 0
            if year != currentYear {
                if let currentYear {
                    result.append(OnThisDayYearSection(year: currentYear, range: sectionStart..<index))
                }
                currentYear = year
                sectionStart = index
            }
        }
        if let currentYear {
            result.append(OnThisDayYearSection(year: currentYear, range: sectionStart..<photos.count))
        }
        sections = result
    }

    // MARK: Deletion

    /// Deletes the given assets via PhotoKit (system shows its own confirm
    /// dialog), then syncs the local index and in-memory state.
    /// Throws `PHPhotosError.userCancelled` if the user cancels.
    func deleteAssets(ids: Set<String>) async throws {
        let assets = ids.compactMap { assetsById[$0] }
        guard !assets.isEmpty else { return }
        try await photoLibrary.deleteAssets(assets)
        // PhotoKit is the source of truth; prune the DB rows right away so
        // the Library grid doesn't show stale entries until the next index run.
        try? metadataDAO.deleteAssets(ids: Array(ids))
        photos.removeAll { ids.contains($0.assetId) }
        for id in ids {
            assetsById.removeValue(forKey: id)
        }
        rebuildSections()
        contentGeneration &+= 1
    }

    func deleteAsset(id: String) async throws {
        try await deleteAssets(ids: [id])
    }

    // MARK: PhotoBrowsingSource

    var photoCount: Int { photos.count }

    func photoId(at index: Int) -> String? {
        photos.indices.contains(index) ? photos[index].assetId : nil
    }

    func index(of assetId: String) -> Int? {
        photos.firstIndex { $0.assetId == assetId }
    }

    func metadata(for assetId: String) -> PhotoMetadata? {
        photos.first { $0.assetId == assetId }
    }

    func asset(for assetId: String) -> PHAsset? {
        assetsById[assetId]
    }

    /// Everything is loaded up front — no pagination.
    func loadNextPageIfNeeded(currentIndex: Int) {}

    func syncFavorite(assetId: String, isFavorite: Bool) {
        try? metadataDAO.updateFavorite(assetId: assetId, isFavorite: isFavorite)
        if let index = photos.firstIndex(where: { $0.assetId == assetId }) {
            photos[index].isFavorite = isFavorite
            contentRefreshGeneration &+= 1
        }
    }

    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata? {
        guard let updated = await indexPipeline.indexSingle(assetId: assetId) else { return nil }
        if let index = photos.firstIndex(where: { $0.assetId == assetId }) {
            photos[index] = updated
            contentRefreshGeneration &+= 1
        }
        return updated
    }

    private nonisolated static func fetchMetadata(
        ids: [String],
        database: AppDatabase
    ) throws -> [String: PhotoMetadata] {
        guard !ids.isEmpty else { return [:] }
        let rows = try database.reader.read { db in
            try PhotoMetadata.fetchAll(db, keys: ids)
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.assetId, $0) })
    }
}
