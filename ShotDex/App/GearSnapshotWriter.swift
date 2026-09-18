import Foundation
import Photos
import UIKit
import WidgetKit

/// Writes the digest the widgets read, into the shared App Group container.
///
/// Deliberately tiny: four numbers, two names and one small cover image. The
/// widgets get no access to the photo library and no copy of any photo's
/// metadata — one thumbnail the user already chose to index, and totals.
@MainActor
struct GearSnapshotWriter {
    let statisticsQueries: StatisticsQueries
    let photoLibrary: PhotoLibraryService

    /// Longest edge of the cover written for the medium widget.
    private static let coverPixels: CGFloat = 400

    func write() async {
        guard let container = GearSnapshot.containerURL else { return }

        // The same queries the Statistics tab runs, so the widget can never
        // disagree with the screen it summarises.
        let total = (try? statisticsQueries.totalPhotos(scope: .allTime)) ?? 0
        let thisMonth = (try? statisticsQueries.totalPhotos(scope: .thisMonth)) ?? 0
        let cameras = (try? statisticsQueries.cameraUsage(scope: .allTime)) ?? []
        let lenses = (try? statisticsQueries.lensUsage(scope: .allTime)) ?? []

        let snapshot = GearSnapshot(
            totalPhotos: total,
            photosThisMonth: thisMonth,
            // The "Unknown" bucket is a real row but not a camera, so it must
            // not become the widget's headline.
            topCamera: cameras.first { !$0.isUnknown }?.name,
            topLens: lenses.first { !$0.isUnknown }?.name,
            generatedAt: .now
        )

        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(
                to: container.appendingPathComponent(GearSnapshot.fileName),
                options: .atomic
            )
        }
        await writeCover(to: container)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Newest photo, small, as the medium widget's cover.
    private func writeCover(to container: URL) async {
        let options = PHFetchOptions()
        options.predicate = PhotoLibraryService.browsableMediaPredicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: options).firstObject else { return }

        let scale = ActiveDisplay.scale
        let size = CGSize(width: Self.coverPixels * scale, height: Self.coverPixels * scale)
        let image: UIImage? = await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestThumbnail(
                for: asset,
                targetSize: size,
                allowNetwork: false
            ) { image in
                guard !hasResumed, let image else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
        guard let data = image?.jpegData(compressionQuality: 0.8) else { return }
        try? data.write(
            to: container.appendingPathComponent(GearSnapshot.coverFileName),
            options: .atomic
        )
    }
}
