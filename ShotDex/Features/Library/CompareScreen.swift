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

/// Mirrors zoom and pan across the compare panes' scroll views.
/// Zoom sync and pan sync toggle independently (Lightroom-style).
@MainActor
final class CompareScrollSynchronizer {
    var isZoomSyncEnabled = true
    var isPanSyncEnabled = true

    /// Weak, because the scrolling column builds and drops panes as they come
    /// and go — a pane that is gone must not be mirrored into forever.
    private var scrollViews: [Int: WeakScrollView] = [:]
    private var isPropagating = false
    /// The last state a gesture produced, replayed onto panes that are built
    /// later so a pane scrolled into view mid-comparison arrives in step.
    private var lastZoomScale: CGFloat?
    private var lastOffsetFraction: CGPoint?

    func register(_ scrollView: UIScrollView, at index: Int) {
        scrollViews[index] = WeakScrollView(view: scrollView)
        guard lastZoomScale != nil || lastOffsetFraction != nil else { return }
        // `makeUIView` runs before the pane has a frame (so no content size to
        // offset against); the catch-up waits for the layout pass after it.
        Task { @MainActor [weak scrollView] in
            guard let scrollView else { return }
            applyStoredState(to: scrollView)
        }
    }

    private struct WeakScrollView {
        weak var view: UIScrollView?
    }

    private var liveScrollViews: [UIScrollView] {
        scrollViews.values.compactMap(\.view)
    }

    private func applyStoredState(to scrollView: UIScrollView) {
        isPropagating = true
        defer { isPropagating = false }
        if isZoomSyncEnabled, let lastZoomScale {
            scrollView.zoomScale = lastZoomScale
        }
        if isPanSyncEnabled, let lastOffsetFraction {
            scrollView.contentOffset = CGPoint(
                x: lastOffsetFraction.x * scrollView.contentSize.width,
                y: lastOffsetFraction.y * scrollView.contentSize.height
            )
        }
    }

    /// Remembers where a gesture left the source pane, for panes built later.
    private func record(_ source: UIScrollView) {
        lastZoomScale = source.zoomScale
        let width = source.contentSize.width
        let height = source.contentSize.height
        guard width > 0, height > 0 else { return }
        lastOffsetFraction = CGPoint(
            x: source.contentOffset.x / width,
            y: source.contentOffset.y / height
        )
    }

    /// Called from scroll-view delegate callbacks; copies the source pane's
    /// zoom and/or normalized offset to the other panes.
    func mirror(from source: UIScrollView) {
        guard !isPropagating else { return }
        record(source)
        guard isZoomSyncEnabled || isPanSyncEnabled else { return }
        isPropagating = true
        defer { isPropagating = false }
        for target in liveScrollViews where target !== source {
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
        guard let source = scrollViews[index]?.view else { return }
        record(source)
        isPropagating = true
        defer { isPropagating = false }
        for target in liveScrollViews where target !== source {
            target.zoomScale = source.zoomScale
        }
    }

    /// Snaps every other pane to pane `index`'s relative position.
    func resyncPan(to index: Int) {
        guard let source = scrollViews[index]?.view else { return }
        record(source)
        isPropagating = true
        defer { isPropagating = false }
        for target in liveScrollViews where target !== source {
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
/// over an `AVPlayerLayer`, participating in the same `CompareScrollSynchronizer`
/// group as image panes so zoom/pan mirror across mixed selections.
private struct CompareVideoPaneView: UIViewRepresentable {
    let player: AVPlayer
    let sync: CompareScrollSynchronizer
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
        // At 1x the pane has nothing to pan, so the drag belongs to whatever
        // scrolls around it (the compare column). Pinch is a separate
        // recognizer, so it stays live.
        scrollView.panGestureRecognizer.isEnabled = false

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
        var sync: CompareScrollSynchronizer?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            playerView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.panGestureRecognizer.isEnabled =
                scrollView.zoomScale / max(scrollView.minimumZoomScale, 0.001) > 1.01
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

/// Compare: one scrolling column of cards, one card per photo — the photo on
/// top, its exposure line and a Delete button underneath. Zoom and pan stay
/// mirrored across every card (no toggles: comparing two photos at different
/// zooms is not a comparison).
struct CompareScreen: View {
    /// Compare needs two photos to mean anything. There is no upper bound.
    static let minPhotoCount = 2
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibraryService.self) private var photoLibrary

    /// Two or more photos, in selection order.
    let photos: [ComparePhoto]
    /// When set (the Duplicates screen), every pane gets a trash toggle bound
    /// to this set of asset ids, and a Delete pill appears while any is marked.
    var deletionMarks: Binding<Set<String>>? = nil
    /// Performs the delete of the marked photos; returns whether anything was
    /// deleted (a cancelled system dialog returns false). The screen closes on
    /// success because its panes would otherwise show photos that are gone.
    var onDeleteMarked: (() async -> Bool)? = nil

    @State private var sync = CompareScrollSynchronizer()
    @State private var isDeleting = false
    /// Photos deleted from inside this screen (no deletion-marks binding), so
    /// their cards leave the column without the caller having to reload.
    @State private var deletedIds: Set<String> = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            cardColumn

            VStack {
                topBar
                Spacer()
                if markedCount > 0 {
                    deletePill
                }
            }
        }
        .statusBarHidden()
        .animation(AppTheme.Motion.standard, value: markedCount > 0)
        .animation(AppTheme.Motion.standard, value: deletedIds)
    }

    /// Photos still on screen: everything the user hasn't deleted from here.
    private var visiblePhotos: [ComparePhoto] {
        photos.filter { photo in
            guard let id = photo.asset?.localIdentifier else { return true }
            return !deletedIds.contains(id)
        }
    }

    private var markedCount: Int {
        guard let deletionMarks else { return 0 }
        return visiblePhotos.filter { photo in
            photo.asset.map { deletionMarks.wrappedValue.contains($0.localIdentifier) } ?? false
        }.count
    }

    /// Bottom pill over the panes: the one place the compare screen deletes
    /// from. Same wording and glyph as the Duplicates screen's bar.
    private var deletePill: some View {
        Button {
            guard let onDeleteMarked, !isDeleting else { return }
            isDeleting = true
            Task {
                let didDelete = await onDeleteMarked()
                isDeleting = false
                if didDelete { dismiss() }
            }
        } label: {
            Label(
                markedCount == 1 ? "Delete 1 Photo" : "Delete \(markedCount) Photos",
                systemImage: "trash"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(Capsule().fill(.red))
            .editorGlass(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
        .padding(.bottom, 16)
        .accessibilityLabel("Delete \(markedCount) marked photos")
    }

    /// One card per photo, one column, scrolling. Cards never go side by side —
    /// a photo cut down to a corner tile can't be judged.
    private var cardColumn: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(visiblePhotos.indices, id: \.self) { index in
                    card(visiblePhotos[index], index: index)
                }
            }
            // Clear of the close button above and the Delete pill below.
            .padding(.horizontal, 12)
            .padding(.top, 72)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func card(_ photo: ComparePhoto, index: Int) -> some View {
        let assetId = photo.asset?.localIdentifier
        let isMarked = deletionMarks.flatMap { marks in
            assetId.map { marks.wrappedValue.contains($0) }
        }
        return CompareCard(
            photo: photo,
            sync: sync,
            paneIndex: index,
            isMarkedForDeletion: isMarked,
            onDelete: { delete(photo) }
        )
    }

    /// The card's Delete button. With a deletion-marks binding (Duplicates) it
    /// marks the photo and the bottom pill does the deleting; without one
    /// (Compare from a selection) it deletes that photo right here, through
    /// PhotoKit's own confirmation.
    private func delete(_ photo: ComparePhoto) {
        guard let asset = photo.asset else { return }
        if let deletionMarks {
            let id = asset.localIdentifier
            if deletionMarks.wrappedValue.contains(id) {
                deletionMarks.wrappedValue.remove(id)
            } else {
                deletionMarks.wrappedValue.insert(id)
            }
            return
        }
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await photoLibrary.deleteAssets([asset])
                deletedIds.insert(asset.localIdentifier)
                // Below two photos there is nothing left to compare.
                if visiblePhotos.count < Self.minPhotoCount { dismiss() }
            } catch {
                // Cancelled confirmation or a failed change request: the card
                // stays, which is the correct outcome either way.
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .editorGlass(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

/// One compare card: the photo (or video) at its own aspect ratio — whole
/// frame, nothing cropped, full card width — with a one-line caption and a red
/// Delete under it. Media keeps the synced zoomable view, so a pinch on one card
/// moves every other card with it.
private struct CompareCard: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let photo: ComparePhoto
    let sync: CompareScrollSynchronizer
    let paneIndex: Int
    /// `nil` when the screen deletes straight away instead of marking first
    /// (Duplicates marks; Compare from a selection deletes).
    var isMarkedForDeletion: Bool? = nil
    let onDelete: () -> Void

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isVideo = false
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 0) {
            media
                // The photo's own shape: cards differ in height, and every
                // frame is shown whole — cropping to a common height would be
                // comparing two different crops.
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    if isVideo, player != nil {
                        playPauseButton
                            .padding(8)
                    }
                }
            infoRow
        }
        .background(EditorTheme.panelSolid)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .overlay {
            if isMarkedForDeletion == true {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .strokeBorder(.red, lineWidth: 3)
            }
        }
        .onAppear(perform: load)
        .onDisappear { player?.pause() }
        // Rewind and show the play icon again when the clip finishes.
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            player?.seek(to: .zero)
            isPlaying = false
        }
    }

    /// Width ÷ height of the asset, orientation applied by PhotoKit. Square
    /// while the asset is missing, so a card never collapses to nothing.
    private var aspectRatio: CGFloat {
        guard let asset = photo.asset, asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 1 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    @ViewBuilder
    private var media: some View {
        if isVideo {
            if let player {
                // Same zoom/pan scroll view as image cards, wrapping an
                // AVPlayerLayer — video participates in sync like a photo.
                CompareVideoPaneView(player: player, sync: sync, paneIndex: paneIndex)
            } else {
                ProgressView().tint(.white)
            }
        } else if let image {
            ZoomableImageView(image: image, sync: sync, paneIndex: paneIndex)
        } else {
            ProgressView().tint(.white)
        }
    }

    /// Under the photo: one line of numbers on the left, Delete on the right.
    private var infoRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(caption ?? "No metadata")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(caption == nil ? EditorTheme.dimText : EditorTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            deleteButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Plain red text — the card is for judging the photo, so the control under
    /// it stays out of the way. Marked (Duplicates) it reads "Keep".
    private var deleteButton: some View {
        Button(action: onDelete) {
            Text(isMarkedForDeletion == true ? "Keep" : "Delete")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(deleteAccessibilityLabel)
        .accessibilityAddTraits(isMarkedForDeletion == true ? .isSelected : [])
    }

    private var deleteAccessibilityLabel: String {
        switch isMarkedForDeletion {
        case true: "Keep this photo"
        case false: "Mark this photo for deletion"
        case nil: "Delete this photo"
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
                .editorGlass(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }

    /// Camera and exposure on one line — the numbers a comparison turns on.
    private var caption: String? {
        guard let metadata = photo.metadata else { return nil }
        return MetadataFormatter.metadataLine([
            metadata.normalizedCameraModel,
            metadata.focalLength.flatMap(MetadataFormatter.focalLength),
            metadata.aperture.flatMap(MetadataFormatter.aperture),
            metadata.shutterSpeedDisplay,
            metadata.iso.flatMap(MetadataFormatter.iso),
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
        let targetSize = ActiveDisplay.pixelSize()
        // Paint the best local rendition first, then replace it with the exact
        // high-quality screen-sized derivative. The latter is cached by the
        // shared service, so revisiting the same comparison is immediate.
        _ = photoLibrary.requestBestLocalImage(
            for: asset,
            targetSize: targetSize
        ) { result in
            guard let result else { return }
            let currentPixels = (image?.size.width ?? 0) * (image?.scale ?? 1)
            let resultPixels = result.size.width * result.scale
            if resultPixels > currentPixels {
                image = result
            }
        }
        _ = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: targetSize,
            allowNetwork: true,
            progress: { _ in }
        ) { result, isDegraded in
            if let result, !isDegraded {
                image = result
            }
        }
    }
}
