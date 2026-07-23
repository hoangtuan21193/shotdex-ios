import AVKit
import Photos
import SwiftUI
import UIKit

/// One photo entering the compare screen. Metadata is optional because
/// videos aren't indexed into the metadata table — they compare fine,
/// just without an EXIF caption.
struct ComparePhoto {
    let metadata: PhotoMetadata?
    let asset: PHAsset?
}

/// Mirrors zoom and pan across the compare panes' scroll views (2–4 panes).
/// Zoom sync and pan sync toggle independently (Lightroom-style).
@MainActor
final class CompareScrollSync {
    var isZoomSyncEnabled = true
    var isPanSyncEnabled = true

    private var scrollViews: [Int: UIScrollView] = [:]
    private var isPropagating = false

    func register(_ scrollView: UIScrollView, at index: Int) {
        scrollViews[index] = scrollView
    }

    /// Called from scroll-view delegate callbacks; copies the source pane's
    /// zoom and/or normalized offset to the other panes.
    func mirror(from source: UIScrollView) {
        guard !isPropagating, isZoomSyncEnabled || isPanSyncEnabled else { return }
        isPropagating = true
        defer { isPropagating = false }
        for (_, target) in scrollViews where target !== source {
            if isZoomSyncEnabled, target.zoomScale != source.zoomScale {
                target.zoomScale = source.zoomScale
            }
            if isPanSyncEnabled {
                target.contentOffset = Self.normalizedOffset(from: source, to: target)
            }
        }
    }

    /// Snaps every other pane to pane `index`'s zoom scale.
    func resyncZoom(to index: Int) {
        guard let source = scrollViews[index] else { return }
        isPropagating = true
        defer { isPropagating = false }
        for (_, target) in scrollViews where target !== source {
            target.zoomScale = source.zoomScale
        }
    }

    /// Snaps every other pane to pane `index`'s relative position.
    func resyncPan(to index: Int) {
        guard let source = scrollViews[index] else { return }
        isPropagating = true
        defer { isPropagating = false }
        for (_, target) in scrollViews where target !== source {
            target.contentOffset = Self.normalizedOffset(from: source, to: target)
        }
    }

    /// Maps an offset between panes proportionally to their content sizes,
    /// so photos with different aspect ratios stay on the same relative spot.
    private static func normalizedOffset(from source: UIScrollView, to target: UIScrollView) -> CGPoint {
        let sw = source.contentSize.width
        let sh = source.contentSize.height
        guard sw > 0, sh > 0 else { return target.contentOffset }
        return CGPoint(
            x: source.contentOffset.x / sw * target.contentSize.width,
            y: source.contentOffset.y / sh * target.contentSize.height
        )
    }
}

/// UIScrollView-backed zoomable video pane: pinch-to-zoom + double-tap zoom
/// over an `AVPlayerLayer`, participating in the same `CompareScrollSync`
/// group as image panes so zoom/pan mirror across mixed selections.
private struct ZoomableVideoView: UIViewRepresentable {
    let player: AVPlayer
    let sync: CompareScrollSync
    let paneIndex: Int

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.contentInsetAdjustmentBehavior = .never

        let playerView = PlayerContainerView()
        playerView.playerLayer.player = player
        playerView.playerLayer.videoGravity = .resizeAspect
        playerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            playerView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            playerView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.playerView = playerView
        context.coordinator.sync = sync
        sync.register(scrollView, at: paneIndex)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.playerView?.playerLayer.player = player
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// UIView whose backing layer is the `AVPlayerLayer`, so the video
    /// resizes with the zooming content view for free.
    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var playerView: PlayerContainerView?
        var sync: CompareScrollSync?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            playerView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            sync?.mirror(from: scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            sync?.mirror(from: scrollView)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: playerView)
                let size = CGSize(
                    width: scrollView.bounds.width / 2.5,
                    height: scrollView.bounds.height / 2.5
                )
                let rect = CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

/// Lightroom-style compare: 2–3 photos stacked vertically, 4 photos in a
/// 2x2 grid, with synchronized zoom and pan toggled independently.
struct CompareScreen: View {
    /// Upper bound for the compare selection (grid layout tops out at 2x2).
    static let maxPhotoCount = 4

    @Environment(\.dismiss) private var dismiss

    /// 2–4 photos, in selection order.
    let photos: [ComparePhoto]

    @State private var sync = CompareScrollSync()
    @State private var isZoomSynced = true
    @State private var isPanSynced = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            paneLayout

            VStack {
                topBar
                Spacer()
            }
        }
        .statusBarHidden()
    }

    @ViewBuilder
    private var paneLayout: some View {
        if photos.count == 4 {
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    pane(0)
                    pane(1)
                }
                HStack(spacing: 1) {
                    pane(2)
                    pane(3)
                }
            }
        } else {
            VStack(spacing: 1) {
                ForEach(photos.indices, id: \.self) { index in
                    pane(index)
                }
            }
        }
    }

    private func pane(_ index: Int) -> some View {
        ComparePane(
            photo: photos[index],
            sync: sync,
            paneIndex: index,
            isCompact: photos.count == 4
        )
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") {
                dismiss()
            }
            Spacer()
            syncToggle(
                isOn: $isZoomSynced,
                title: "Zoom",
                systemImage: "plus.magnifyingglass",
                hint: "Zoom all panes together"
            ) {
                sync.isZoomSyncEnabled = isZoomSynced
                if isZoomSynced { sync.resyncZoom(to: 0) }
            }
            syncToggle(
                isOn: $isPanSynced,
                title: "Move",
                systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                hint: "Move all panes together"
            ) {
                sync.isPanSyncEnabled = isPanSynced
                if isPanSynced { sync.resyncPan(to: 0) }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Filter-chip toggle over the black backdrop: icon + short word,
    /// ON = solid accent capsule + white text (that gesture mirrors across
    /// panes), OFF = dim glass capsule (each pane independent).
    private func syncToggle(
        isOn: Binding<Bool>,
        title: String,
        systemImage: String,
        hint: String,
        onChange: @escaping () -> Void
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            onChange()
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background {
                    if isOn.wrappedValue {
                        Capsule().fill(Color.accentColor)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(isOn.wrappedValue ? 0.2 : 0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hint)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}

/// One compare pane: loads its image, then shows the synced zoomable view
/// with a small metadata caption.
private struct ComparePane: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let photo: ComparePhoto
    let sync: CompareScrollSync
    let paneIndex: Int
    /// Quarter-screen panes (2x2 grid) drop the camera model from the caption.
    let isCompact: Bool

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isVideo = false
    @State private var isPlaying = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if isVideo {
                if let player {
                    // Same zoom/pan scroll view as image panes, wrapping an
                    // AVPlayerLayer — video participates in sync like a photo.
                    ZoomableVideoView(player: player, sync: sync, paneIndex: paneIndex)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            } else if let image {
                ZoomableImageView(image: image, sync: sync, paneIndex: paneIndex)
            } else {
                ProgressView()
                    .tint(.white)
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isVideo, player != nil {
                playPauseButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear(perform: load)
        .onDisappear { player?.pause() }
        // Rewind and show the play icon again when the clip finishes.
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            player?.seek(to: .zero)
            isPlaying = false
        }
    }

    /// Small glass play/pause control — the zoomable wrapper replaces the
    /// native AVKit transport, so the pane needs its own toggle.
    private var playPauseButton: some View {
        Button {
            guard let player else { return }
            if isPlaying {
                player.pause()
            } else {
                player.play()
            }
            isPlaying.toggle()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .padding(8)
    }

    private var caption: String? {
        guard let metadata = photo.metadata else { return nil }
        return FormatUtils.metadataLine([
            isCompact ? nil : metadata.normalizedCameraModel,
            metadata.focalLength.flatMap(FormatUtils.focalLength),
            metadata.aperture.flatMap(FormatUtils.aperture),
            metadata.iso.flatMap(FormatUtils.iso),
        ])
    }

    private func load() {
        guard let asset = photo.asset else { return }
        if asset.mediaType == .video {
            isVideo = true
            loadVideo(asset)
        } else {
            loadImage(asset)
        }
    }

    /// Manual playback, muted by default so side-by-side panes don't clash audio.
    private func loadVideo(_ asset: PHAsset) {
        guard player == nil else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            guard let item else { return }
            Task { @MainActor in
                let avPlayer = AVPlayer(playerItem: item)
                avPlayer.isMuted = true
                player = avPlayer
            }
        }
    }

    private func loadImage(_ asset: PHAsset) {
        guard image == nil else { return }
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * scale,
            height: UIScreen.main.bounds.height * scale
        )
        // Compare loads the screen-sized derivative eagerly on open
        // (`allowNetwork: true`) so every pane shows its photo immediately —
        // iCloud serves a screen-sized rendition (fast), not the multi-MB
        // original. `.opportunistic` paints a local preview first so panes
        // aren't blank while the derivatives stream.
        _ = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: targetSize,
            allowNetwork: true,
            progress: { _ in }
        ) { result, _ in
            if let result {
                image = result
            }
        }
    }
}
