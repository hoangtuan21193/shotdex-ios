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

    /// Longest edge in pixels. A large widget is about 360 pt wide, so 1000 px
    /// covers a 3x screen with room to crop, and costs ~200 KB per frame.
    static let maxPixels: CGFloat = 1_000
    static let compressionQuality: CGFloat = 0.8

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
