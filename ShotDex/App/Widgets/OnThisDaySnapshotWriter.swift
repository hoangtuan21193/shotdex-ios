import Foundation
import Photos
import WidgetKit

/// Precomputes the On This Day widget's few days: how many photos each day
/// has, which years they span, and a handful of small JPEGs.
///
/// The widget cannot do this itself — it has no PhotoKit access by design
/// (§7.4b) — and the fetch behind it is a compound OR-predicate scan of the
/// whole library, which is not something to run on a widget refresh schedule.
/// So the app writes today and the next couple of days whenever it is opened,
/// and the widget's timeline just steps from one file to the next at midnight.
@MainActor
struct OnThisDaySnapshotWriter {
    let photoLibrary: PhotoLibraryService
    var calendar: Calendar = .current

    /// A rewrite is skipped while today's file is fresher than this: the fetch
    /// is expensive and the answer only changes when the library does.
    private static let staleAfter: TimeInterval = 6 * 3600

    func write(now: Date = .now, force: Bool = false) async {
        guard let container = WidgetSharedContainer.url else { return }
        let directory = OnThisDaySnapshot.directoryURL(in: container)
        let days = Self.days(from: now, calendar: calendar)
        guard force || Self.needsRewrite(days: days, now: now, calendar: calendar) else { return }

        var keptFiles: Set<String> = []
        for day in days {
            let dayKey = WidgetSharedContainer.dayKey(for: day, calendar: calendar)
            let snapshot = await write(day: day, dayKey: dayKey, directory: directory)
            keptFiles.insert(OnThisDaySnapshot.fileName(dayKey: dayKey))
            keptFiles.formUnion(snapshot?.photos.map(\.fileName) ?? [])
        }
        WidgetImageRenderer.prune(directory: directory, keeping: keptFiles)
        WidgetCenter.shared.reloadTimelines(ofKind: OnThisDaySnapshot.widgetKind)
    }

    /// Today first, then the days the widget will roll over to before the app
    /// is likely to be opened again.
    static func days(from now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0...OnThisDaySnapshot.daysAhead).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    /// True when any day is missing its file, or today's is old enough that the
    /// library has probably changed under it. Pure, so the throttle is tested.
    static func needsRewrite(days: [Date], now: Date, calendar: Calendar) -> Bool {
        guard let today = days.first else { return false }
        for day in days {
            let key = WidgetSharedContainer.dayKey(for: day, calendar: calendar)
            guard OnThisDaySnapshot.read(dayKey: key) != nil else { return true }
        }
        let todayKey = WidgetSharedContainer.dayKey(for: today, calendar: calendar)
        guard let snapshot = OnThisDaySnapshot.read(dayKey: todayKey) else { return true }
        return now.timeIntervalSince(snapshot.generatedAt) > staleAfter
    }

    private func write(day: Date, dayKey: String, directory: URL) async -> OnThisDaySnapshot? {
        let candidates = await Task.detached(priority: .utility) {
            Self.candidates(for: day, calendar: calendar)
        }.value

        let featured = OnThisDaySnapshot.featuredIndices(years: candidates.years)
        let renderer = WidgetImageRenderer(photoLibrary: photoLibrary)
        var photos: [OnThisDaySnapshot.Photo] = []
        for (slot, index) in featured.enumerated() {
            let asset = candidates.assets[index]
            let fileName = OnThisDaySnapshot.imageFileName(dayKey: dayKey, index: slot)
            let url = directory.appendingPathComponent(fileName)
            // Local only: this runs on launch and on every foreground, and
            // pulling originals out of iCloud for a widget nobody may have
            // installed is not a cost the user agreed to.
            guard await renderer.write(asset: asset, to: url, allowNetwork: false) else { continue }
            photos.append(
                OnThisDaySnapshot.Photo(
                    assetId: asset.localIdentifier,
                    year: candidates.years[index],
                    fileName: fileName
                )
            )
        }

        let snapshot = OnThisDaySnapshot(
            dayKey: dayKey,
            photoCount: candidates.count,
            years: Array(Set(candidates.years)).sorted(by: >),
            photos: photos,
            generatedAt: .now
        )
        try? WidgetSharedContainer.encode(
            snapshot,
            to: directory.appendingPathComponent(OnThisDaySnapshot.fileName(dayKey: dayKey))
        )
        return snapshot
    }

    /// PHAsset is not Sendable, but PhotoKit fetches are thread-safe — the same
    /// escape hatch `AlbumsModel.Snapshot` uses to cross the off-main boundary.
    private struct Candidates: @unchecked Sendable {
        var assets: [PHAsset]
        var years: [Int]
        var count: Int
    }

    /// The leading photos of the day across previous years, newest first, plus
    /// the true total. Only the leading few are materialised: the widget shows
    /// four, and pulling 3,000 assets into an array to drop all but four is
    /// work for nothing.
    private nonisolated static func candidates(for day: Date, calendar: Calendar) -> Candidates {
        let fetch = OnThisDayModel.fetchAssets(for: day, calendar: calendar)
        // Enough to cover several years even when one year dominates the day.
        let scanLimit = min(fetch.count, 60)
        var assets: [PHAsset] = []
        var years: [Int] = []
        assets.reserveCapacity(scanLimit)
        for index in 0..<scanLimit {
            let asset = fetch.object(at: index)
            guard let creationDate = asset.creationDate else { continue }
            assets.append(asset)
            years.append(calendar.component(.year, from: creationDate))
        }
        return Candidates(assets: assets, years: years, count: fetch.count)
    }
}
