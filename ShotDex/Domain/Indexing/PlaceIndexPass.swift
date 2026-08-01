import Foundation
import OSLog

/// Fills in where each photo was taken, one place at a time.
///
/// Runs after an index run rather than inside it. The EXIF pass is local work
/// bounded by disk speed; this is network work bounded by someone else's rate
/// limit, and gluing the two together would make the indexing indicator hang
/// around for a quarter of an hour on a big library. It is resumable instead:
/// every cell it finishes is committed, so a run that is cancelled, throttled or
/// interrupted by the app being suspended simply picks up where it stopped.
///
/// Work is measured in **cells**, not photos — see `PlaceCellKey`. A library of
/// twenty thousand photos is usually a few hundred to a couple of thousand
/// distinct cells, which is the difference between this being possible and not.
actor PlaceIndexPass {
    struct Summary: Equatable, Sendable {
        var resolvedCells = 0
        var cachedCells = 0
        var photosDescribed = 0
        /// Stopped early because the geocoder went quiet — offline or throttled.
        /// The next run continues; nothing is lost and nothing is marked wrong.
        var stoppedForBackoff = false
        var wasCancelled = false

        var didWork: Bool { resolvedCells > 0 || cachedCells > 0 }
    }

    /// Cells fetched per batch. Small: the list is re-queried each time, so a
    /// cell resolved from cache by a parallel path is not asked for twice.
    private static let cellBatchSize = 25
    /// Rows stamped with a cell key per batch, and the cap on stamping loops so a
    /// library arriving faster than this drains over several runs instead of
    /// holding one open forever.
    private static let stampBatchSize = 2_000
    private static let maximumStampBatches = 50

    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "places")

    private let store: PlaceStore
    private let geocoder: PlaceGeocodingService
    private var isRunning = false
    private var isCancelled = false

    init(store: PlaceStore, geocoder: PlaceGeocodingService) {
        self.store = store
        self.geocoder = geocoder
    }

    /// - Parameters:
    ///   - isEnabled: re-read per cell, not latched at the start — the user can
    ///     turn the setting off mid-run and expect it to take effect.
    ///   - onProgress: photos still without a place, after each cell.
    @discardableResult
    func run(
        isEnabled: @escaping @Sendable () -> Bool = { true },
        onProgress: @escaping @Sendable (Int) -> Void = { _ in }
    ) async -> Summary {
        guard !isRunning else { return Summary() }
        isRunning = true
        isCancelled = false
        defer { isRunning = false }

        var summary = Summary()
        guard isEnabled() else { return summary }

        // Rows written before this feature existed — or before their coordinates
        // arrived — have no cell key yet, and the work list groups by it in SQL.
        for _ in 0..<Self.maximumStampBatches {
            guard !isCancelled, !Task.isCancelled else {
                summary.wasCancelled = true
                return summary
            }
            let stamped = (try? store.stampMissingCellKeys(limit: Self.stampBatchSize)) ?? 0
            if stamped < Self.stampBatchSize { break }
        }

        while !isCancelled, !Task.isCancelled, isEnabled() {
            guard let cells = try? store.pendingCells(limit: Self.cellBatchSize),
                  !cells.isEmpty
            else { break }

            for cell in cells {
                guard !isCancelled, !Task.isCancelled, isEnabled() else { break }
                let wasCached = (try? store.cachedCell(
                    key: cell.cellKey,
                    localeIdentifier: Locale.current.identifier
                ))?.resolvedAt != nil
                let outcome = await geocoder.resolveCell(
                    key: cell.cellKey,
                    latitude: cell.latitude,
                    longitude: cell.longitude
                )
                switch outcome {
                case .resolved:
                    if wasCached { summary.cachedCells += 1 } else { summary.resolvedCells += 1 }
                    summary.photosDescribed += cell.photoCount
                case .empty:
                    summary.resolvedCells += 1
                case .unavailable:
                    // Offline or throttled. Stop the whole run: the next cell
                    // would fail the same way, and queueing failures is how an
                    // app earns a longer throttle.
                    summary.stoppedForBackoff = true
                    Self.logger.log("place pass stopped: geocoder unavailable")
                    onProgress((try? store.pendingPhotoCount()) ?? 0)
                    return summary
                }
                onProgress((try? store.pendingPhotoCount()) ?? 0)
            }
        }

        summary.wasCancelled = isCancelled || Task.isCancelled
        if summary.didWork {
            Self.logger.log(
                """
                place pass: \(summary.resolvedCells) cells geocoded, \
                \(summary.cachedCells) from cache, \
                \(summary.photosDescribed) photos described
                """
            )
        }
        return summary
    }

    func cancel() {
        isCancelled = true
    }

    /// Photos with coordinates and no address yet.
    func pendingPhotoCount() -> Int {
        (try? store.pendingPhotoCount()) ?? 0
    }
}
