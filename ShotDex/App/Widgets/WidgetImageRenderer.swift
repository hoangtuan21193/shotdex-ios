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

    /// Bumped when the way a frame is produced changes, so files written by an
    /// older build are rendered again instead of staying as they are. Version 2
    /// is "waits for the final, sharp rendition"; version 1 wrote whatever
    /// arrived first, which with `.opportunistic` delivery is the blurred
    /// preview.
    static let version = 2

    /// Renders `asset` into `url`, returning false when PhotoKit had nothing to
    /// give (an iCloud-only asset with no network, a deleted one).
    @discardableResult
    func write(asset: PHAsset, to url: URL, allowNetwork: Bool = true) async -> Bool {
        let size = CGSize(width: Self.maxPixels, height: Self.maxPixels)
        var image = await finalImage(
            for: asset, targetSize: size, contentMode: .aspectFit, allowNetwork: false
        )
        // An on-device copy that is not the size that was asked for is an
        // Optimize Storage proxy, whatever PhotoKit says about being final.
        // The user chose this picture, so it is worth the download.
        if allowNetwork, image?.isSharp != true {
            image = await finalImage(
                for: asset, targetSize: size, contentMode: .aspectFit, allowNetwork: true
            ) ?? image
        }
        guard let data = image?.image.jpegData(compressionQuality: Self.compressionQuality)
        else { return false }
        return Self.write(data, to: url)
    }

    /// A small copy for a menu row, where the widget's own size would be a
    /// hundred times more than the row can show.
    @discardableResult
    func writeThumbnail(for asset: PHAsset, to url: URL, maxPixels: CGFloat) async -> Bool {
        let size = CGSize(width: maxPixels, height: maxPixels)
        // Local only: a menu row is not worth a download, and at 180 px even a
        // proxy has the pixels.
        let image = await finalImage(
            for: asset, targetSize: size, contentMode: .aspectFill, allowNetwork: false
        )
        guard let data = image?.image.jpegData(compressionQuality: 0.7) else { return false }
        return Self.write(data, to: url)
    }

    /// The **last** rendition PhotoKit sends, not the first.
    ///
    /// `.opportunistic` delivery calls back twice: a fast blurred preview, then
    /// the real thing. Taking the first non-nil image — which this renderer did
    /// until now — means every widget picture on disk was the preview, and it
    /// stayed that way until the file was rewritten hours later.
    private func finalImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        allowNetwork: Bool
    ) async -> (image: UIImage, isSharp: Bool)? {
        await withCheckedContinuation { continuation in
            var hasResumed = false
            var latest: UIImage?
            _ = photoLibrary.requestThumbnail(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                allowNetwork: allowNetwork
            ) { image, delivery in
                if let image { latest = image }
                guard delivery.isFinal, !hasResumed else { return }
                hasResumed = true
                guard let result = latest else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (result, delivery.isSharp))
            }
        }
    }

    private static func write(_ data: Data, to url: URL) -> Bool {
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
