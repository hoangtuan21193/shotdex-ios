import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Plays the motion of a Live Photo over the still the viewer is already
/// showing.
///
/// Overlaid rather than used in place of `ZoomableImageView` for two reasons:
/// `PHLivePhotoView` has no zoom of its own, and its built-in press-and-hold
/// recognizer fights the pager's swipe. So the still keeps pinch and paging,
/// and this appears only for the length of one playback, started from the LIVE
/// badge the way Photos starts it from its own badge.
struct LivePhotoPlayerView: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    /// Fired when playback ends, so the host can take the overlay away again.
    let onFinish: () -> Void

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.delegate = context.coordinator
        view.isMuted = false
        // The badge is the control; the view itself must not steal the pager's
        // swipe or the scroll view's pinch while it is up.
        view.isUserInteractionEnabled = false
        view.livePhoto = livePhoto
        view.startPlayback(with: .full)
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        context.coordinator.onFinish = onFinish
        if view.livePhoto !== livePhoto {
            view.livePhoto = livePhoto
            view.startPlayback(with: .full)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func livePhotoView(
            _ livePhotoView: PHLivePhotoView,
            didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle
        ) {
            onFinish()
        }
    }
}

/// The LIVE pill Photos puts in the top-left of a Live Photo, here as the
/// control that starts playback.
struct LivePhotoBadge: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "livephoto")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolEffect(.pulse, isActive: isPlaying)
                Text("LIVE")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.black.opacity(0.45), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Playing Live Photo" : "Play Live Photo")
    }
}

/// Loading and exporting the motion half of a Live Photo.
enum LivePhotoLoader {
    /// Requests the `PHLivePhoto` for an asset at display size. Network access
    /// is allowed because an iCloud-only Live Photo has no local motion track.
    static func load(asset: PHAsset, targetSize: CGSize) async -> PHLivePhoto? {
        await withCheckedContinuation { continuation in
            let options = PHLivePhotoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            var hasResumed = false
            PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { livePhoto, info in
                // `.highQualityFormat` still delivers a degraded pass first for
                // Live Photos, so resume on the first non-degraded result only.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !hasResumed, !isDegraded else { return }
                hasResumed = true
                continuation.resume(returning: livePhoto)
            }
        }
    }

    /// Writes the paired video of a Live Photo to a temporary file, for "Save
    /// as Video". Returns `nil` when the asset has no motion track.
    static func exportVideo(asset: PHAsset) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .pairedVideo })
            ?? resources.first(where: { $0.type == .fullSizePairedVideo })
        else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotdex-live-\(UUID().uuidString).mov")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let succeeded: Bool = await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(
                for: resource, toFile: url, options: options
            ) { error in
                continuation.resume(returning: error == nil)
            }
        }
        return succeeded ? url : nil
    }
}
