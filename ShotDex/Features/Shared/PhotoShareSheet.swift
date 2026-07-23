import AVFoundation
import Photos
import UIKit

/// Shared multi-asset share plumbing. Gathers shareable items for a set of
/// assets (downloading from iCloud when needed) and presents a single system
/// share sheet from the top-most view controller.
enum PhotoShareSheet {
    /// Resolves shareable items for the given assets, in order. Images share
    /// their original data; videos share a file URL. iCloud-only assets are
    /// downloaded (`isNetworkAccessAllowed = true`); any that still fail are
    /// skipped rather than aborting the whole share.
    static func gather(assets: [PHAsset]) async -> [Any] {
        var items: [Any] = []
        for asset in assets {
            if asset.mediaType == .video {
                if let url = await videoURL(for: asset) { items.append(url) }
            } else if let data = await imageData(for: asset) {
                items.append(data)
            }
        }
        return items
    }

    /// Presents one `UIActivityViewController` for the gathered items. No-op if
    /// there's nothing to share or no foreground window.
    @MainActor
    static func present(items: [Any]) {
        guard !items.isEmpty,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController
        else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        presenter.present(activity, animated: true)
    }

    private static func imageData(for asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        // highQualityFormat delivers a single callback (no progressive passes),
        // so resuming the continuation once is safe.
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func videoURL(for asset: PHAsset) async -> URL? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
    }
}
