import Foundation
import Photos
import UIKit

/// Turns a `PHAsset` into the small JPEG a widget can paint.
///
/// Widgets get pictures this way and no other: a widget process cannot reach
/// the photo library, and even if it could, decoding a full-resolution frame
/// inside one is how a widget gets killed. The app renders a capped copy into
/// the App Group and the widget loads that file.
@MainActor
struct WidgetImageRenderer {
    let photoLibrary: PhotoLibraryService

    /// Longest edge in pixels.
    ///
    /// 1000 px was too few and it showed: a large widget is 329 × 345 pt, so a
    /// 3x screen wants about 1035 px down the *short* edge — a landscape frame
    /// capped at 1000 px on its long edge arrives already enlarged, and the
    /// preview in Settings looked soft before anything was zoomed. 1600 px
    /// covers the large family with room, and leaves something for the pinch
    /// zoom to eat into. About 450 KB a frame.
    static let maxPixels: CGFloat = 1_600
    static let compressionQuality: CGFloat = 0.85

    /// Renders `asset` into `url`, returning false when PhotoKit had nothing to
    /// give (an iCloud-only asset with no network, a deleted one).
    @discardableResult
    func write(asset: PHAsset, to url: URL, allowNetwork: Bool = true) async -> Bool {
        let size = CGSize(width: Self.maxPixels, height: Self.maxPixels)
        let image: UIImage? = await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestThumbnail(
                for: asset,
                targetSize: size,
                contentMode: .aspectFit,
                allowNetwork: allowNetwork
            ) { image in
                // `.opportunistic` fires twice; the degraded preview is not
                // worth writing over a good file, so only the first non-nil
                // result of a finished request is taken.
                guard !hasResumed, let image else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
        guard let data = image?.jpegData(compressionQuality: Self.compressionQuality) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// A small copy for a menu row, where the widget's own size would be a
    /// hundred times more than the row can show.
    @discardableResult
    func writeThumbnail(for asset: PHAsset, to url: URL, maxPixels: CGFloat) async -> Bool {
        let size = CGSize(width: maxPixels, height: maxPixels)
        let image: UIImage? = await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestThumbnail(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                allowNetwork: false
            ) { image in
                guard !hasResumed, let image else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
        guard let data = image?.jpegData(compressionQuality: 0.7) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Deletes everything in `directory` whose name is not in `keeping` — the
    /// frames of days and albums the user has moved on from. The container is
    /// the app's own, so a stale file is never reclaimed by anything else.
    static func prune(directory: URL, keeping names: Set<String>) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries where !names.contains(entry.lastPathComponent) {
            try? manager.removeItem(at: entry)
        }
    }
}
