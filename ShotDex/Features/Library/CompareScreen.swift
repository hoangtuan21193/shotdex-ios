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
    /// A plain tap on the frame, so a video card is picked the same way a photo
    /// card is. Waits for the double-tap to fail — see `ZoomableImageView`.
    var onSingleTap: (() -> Void)?

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
        // And past 1x it still only answers to two fingers, so one finger
        // always scrolls the column — see `ZoomableImageView`.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2

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

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap)
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.playerView?.playerLayer.player = player
        context.coordinator.onSingleTap = onSingleTap
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

        var onSingleTap: (() -> Void)?

        @objc func handleSingleTap() {
            onSingleTap?()
        }

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


/// Compare: one card per photo, and one verb. Zoom and pan stay mirrored
/// across every card (no toggles: comparing two photos at different zooms is
/// not a comparison).
///
/// **Tapping a photo marks it for deletion**, and that is the only thing a tap
/// here does. The screen says so in the top bar before anything is marked,
/// because a selection that means nothing until an action is picked later is a
/// selection nobody can make: faced with eight frames and a row of empty
/// circles, the first question is "am I ticking the ones I keep or the ones I
/// lose", and no arrangement of buttons answers it as well as not having the
/// question. It is also the same gesture, the same red, and the same badge as
/// the Duplicates grid this screen is usually opened from — the opposite
/// meaning two taps apart would be worse than either meaning alone.
///
/// One column on a phone, two or three on an iPad or the Duo's inner display
/// (`CompareLayout`).
struct CompareScreen: View {
    /// Compare needs two photos to mean anything. There is no upper bound.
    static let minPhotoCount = 2
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibraryService.self) private var photoLibrary

    /// Two or more photos, in selection order.
    let photos: [ComparePhoto]
    /// When set (the Duplicates screen), marks are written here and that screen
    /// owns the delete; without it this screen marks locally and deletes itself.
    var deletionMarks: Binding<Set<String>>? = nil
    /// Deletes exactly the ids handed to it — the marks among *these* cards,
    /// never whatever else the caller has marked elsewhere — and returns
    /// whether anything went (a cancelled system dialog returns false). The
    /// screen closes on success because its cards would otherwise show photos
    /// that are gone.
    var onDeleteMarked: ((Set<String>) async -> Bool)? = nil

    @State private var sync = CompareScrollSynchronizer()
    /// Marks made here when no binding was handed in. Same meaning as the
    /// binding, so the rest of the screen never asks which flow it is in.
    @State private var localMarks: Set<String> = []
    @State private var isDeleting = false
    /// Photos deleted from inside this screen, so their cards leave the layout
    /// without the caller having to reload.
    @State private var deletedIds: Set<String> = []

    private static let cardSpacing: CGFloat = 14
    private static let horizontalPadding: CGFloat = 12

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cards
            VStack {
                topBar
                Spacer()
            }
        }
        .statusBarHidden()
        .animation(AppTheme.Motion.standard, value: markedCount)
        .animation(AppTheme.Motion.standard, value: deletedIds)
    }

    // MARK: Marks

    /// Where marks live: the caller's set in the Duplicates flow, this screen's
    /// own otherwise. One accessor so no caller has to know which.
    private var markedIds: Set<String> {
        get { deletionMarks?.wrappedValue ?? localMarks }
        nonmutating set {
            if let deletionMarks {
                deletionMarks.wrappedValue = newValue
            } else {
                localMarks = newValue
            }
        }
    }

    /// Photos still on screen: everything the user hasn't deleted from here.
    private var visiblePhotos: [ComparePhoto] {
        photos.filter { photo in
            guard let id = photo.assetId else { return true }
            return !deletedIds.contains(id)
        }
    }

    /// Marks that still have a card, so a deleted photo can never keep a stale
    /// id in the count the Delete button is about to act on.
    private var markedPhotos: [ComparePhoto] {
        visiblePhotos.filter { $0.assetId.map(markedIds.contains) ?? false }
    }

    private var markedCount: Int { markedPhotos.count }

    private func toggleMark(_ photo: ComparePhoto) {
        guard let id = photo.assetId else { return }
        if markedIds.contains(id) {
            markedIds.remove(id)
        } else {
            markedIds.insert(id)
        }
    }

    /// The shortcut the screen exists for: eight frames of one moment, one
    /// keeper. Marking the other seven by hand is seven taps of the same
    /// decision. In the card's long-press menu, where the Duplicates grid keeps
    /// its "Keep Only This" — the same place, so it is learned once.
    private func markAllOthers(than photo: ComparePhoto) {
        guard let keeper = photo.assetId else { return }
        markedIds = markedIds
            .union(visiblePhotos.compactMap(\.assetId))
            .subtracting([keeper])
    }

    // MARK: Layout

    /// The cards, in as many columns as the width can hold.
    ///
    /// Columns are built as separate `LazyVStack`s rather than a `LazyVGrid`:
    /// cards are as tall as their photo is, and a grid would align every row to
    /// its tallest card, leaving a ragged gap under every short one.
    /// `CompareLayout.distribute` deals each card to the shortest column so the
    /// bottom edge stays roughly level.
    private var cards: some View {
        GeometryReader { proxy in
            let available = proxy.size.width - Self.horizontalPadding * 2
            let visible = visiblePhotos
            let columnCount = CompareLayout.columns(
                count: visible.count,
                width: available,
                spacing: Self.cardSpacing
            )
            let buckets = CompareLayout.distribute(
                aspectRatios: visible.map(\.aspectRatio),
                columns: columnCount
            )

            ScrollView {
                HStack(alignment: .top, spacing: Self.cardSpacing) {
                    ForEach(buckets.indices, id: \.self) { column in
                        LazyVStack(spacing: Self.cardSpacing) {
                            ForEach(buckets[column], id: \.self) { index in
                                card(visible[index], index: index)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                // Clear of the top bar.
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.top, 72)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func card(_ photo: ComparePhoto, index: Int) -> some View {
        CompareCard(
            photo: photo,
            sync: sync,
            paneIndex: index,
            isMarked: photo.assetId.map(markedIds.contains) ?? false,
            canMarkOthers: visiblePhotos.count > 1,
            onToggleMark: { toggleMark(photo) },
            onMarkAllOthers: { markAllOthers(than: photo) }
        )
    }

    // MARK: Top bar

    /// Close on the left; on the right either what a tap does, or what the
    /// taps so far add up to. The two never appear together and they occupy the
    /// same corner, so the place that answers "what now" is always one place.
    private var topBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
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

            Spacer(minLength: AppTheme.Spacing.sm)

            if markedCount > 0 {
                deleteButton
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                hint
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// The instruction, in the corner the Delete button will appear in. It is
    /// the answer to the only question a first-time user of this screen has,
    /// and it costs nothing once they know it — it is gone the moment they
    /// mark anything.
    private var hint: some View {
        Text("Tap a photo to mark it for deletion")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
            .frame(maxWidth: 190, alignment: .trailing)
            .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
            .accessibilityHidden(true)
    }

    /// One button, one verb, and the count it will act on. Red because it
    /// deletes; no menu, because there is nothing to choose between.
    private var deleteButton: some View {
        Button(action: deleteMarked) {
            Label(
                markedCount == 1 ? "Delete 1 Photo" : "Delete \(markedCount) Photos",
                systemImage: "trash"
            )
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(Capsule().fill(.red))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
        .accessibilityLabel("Delete \(markedCount) marked photos")
    }

    // MARK: Deleting

    /// The Duplicates screen owns its own delete (it has a confirmation and a
    /// list to refresh), so there the button hands back to it. Everywhere else
    /// this screen deletes, and PhotoKit's own alert ("Delete 7 Photos?") is
    /// the confirmation — a second one of ours in front of it would be two
    /// dialogs for one decision.
    private func deleteMarked() {
        guard !isDeleting, markedCount > 0 else { return }
        if let onDeleteMarked {
            let ids = Set(markedPhotos.compactMap(\.assetId))
            isDeleting = true
            Task {
                let didDelete = await onDeleteMarked(ids)
                isDeleting = false
                if didDelete { dismiss() }
            }
            return
        }
        performDelete(markedPhotos.compactMap(\.asset))
    }

    /// One change request for the batch, and the screen closes once there is
    /// nothing left to compare. A cancelled dialog throws, and the cards stay
    /// marked — the correct outcome either way.
    private func performDelete(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await photoLibrary.deleteAssets(assets)
                let gone = Set(assets.map(\.localIdentifier))
                deletedIds.formUnion(gone)
                markedIds.subtract(gone)
                if visiblePhotos.count < Self.minPhotoCount { dismiss() }
            } catch {
                // Cancelled confirmation or a failed change request.
            }
        }
    }
}
extension ComparePhoto {
    var assetId: String? { asset?.localIdentifier }

    /// Width ÷ height with PhotoKit's orientation applied; square when the
    /// asset is missing, so a card never collapses to nothing.
    var aspectRatio: CGFloat {
        guard let asset, asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 1 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }
}

/// One compare card: the photo (or video) at its own aspect ratio — whole
/// frame, nothing cropped, full card width — with its numbers on a single line
/// underneath. Media keeps the synced zoomable view, so a pinch on one card
/// moves every other card with it.
///
/// The whole card is the control: tapping the frame or the numbers marks the
/// photo for deletion. No buttons of its own — see `CompareScreen`.
private struct CompareCard: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let photo: ComparePhoto
    let sync: CompareScrollSynchronizer
    let paneIndex: Int
    let isMarked: Bool
    /// False when this is the last photo left, where "mark all others" would
    /// mark nothing.
    let canMarkOthers: Bool
    let onToggleMark: () -> Void
    let onMarkAllOthers: () -> Void

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isVideo = false
    @State private var isPlaying = false

    private var borderColor: Color? { isMarked ? .red : nil }

    var body: some View {
        VStack(spacing: 0) {
            media
                // The photo's own shape: cards differ in height, and every
                // frame is shown whole — cropping to a common height would be
                // comparing two different crops.
                .aspectRatio(photo.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) { markBadge }
                .overlay(alignment: .bottomTrailing) {
                    if isVideo, player != nil {
                        playPauseButton
                            .padding(8)
                    }
                }
            caption
        }
        .background(EditorTheme.panelSolid)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .overlay {
            if let borderColor {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 3)
            }
        }
        // A marked photo is on its way out; dimming it says so without
        // covering the frame, the same as the Duplicates grid's tiles.
        .opacity(isMarked ? 0.82 : 1)
        .contextMenu {
            if canMarkOthers {
                Button(role: .destructive, action: onMarkAllOthers) {
                    Label("Keep Only This", systemImage: "checkmark.circle")
                }
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isMarked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(
            named: isMarked ? "Unmark" : "Mark for deletion",
            onToggleMark
        )
        .accessibilityAction(named: "Keep only this", onMarkAllOthers)
    }

    @ViewBuilder
    private var media: some View {
        if isVideo {
            if let player {
                // Same zoom/pan scroll view as image cards, wrapping an
                // AVPlayerLayer — video participates in sync like a photo.
                CompareVideoPaneView(
                    player: player,
                    sync: sync,
                    paneIndex: paneIndex,
                    onSingleTap: onToggleMark
                )
            } else {
                ProgressView().tint(.white)
            }
        } else if let image {
            ZoomableImageView(
                image: image,
                sync: sync,
                paneIndex: paneIndex,
                onSingleTap: onToggleMark,
                panRequiresTwoFingers: true
            )
        } else {
            ProgressView().tint(.white)
        }
    }

    /// The same red trash badge the Duplicates grid stamps on a marked tile.
    /// Hollow rather than absent when the photo is not marked: an empty circle
    /// on every card is what says the frames are tappable at all, on a screen
    /// whose buttons have otherwise moved to the top bar.
    private var markBadge: some View {
        Image(systemName: isMarked ? "trash.circle.fill" : "circle")
            .font(.system(size: 26))
            .symbolRenderingMode(isMarked ? .palette : .monochrome)
            .foregroundStyle(
                isMarked ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.9)),
                AnyShapeStyle(Color.red)
            )
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .padding(10)
            .allowsHitTesting(false)
    }

    /// Camera, exposure and file size on one line — the numbers a comparison
    /// turns on. Size last because it is the tie-breaker, not the question: two
    /// frames of the same scene are told apart by the exposure first, and by
    /// which one is the bigger original when they look the same.
    ///
    /// Also the card's second hit target: a strip the full width of the card,
    /// for the photo that is zoomed in and being panned rather than picked.
    private var caption: some View {
        Button(action: onToggleMark) {
            Text(captionText ?? "No metadata")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(captionText == nil ? EditorTheme.dimText : EditorTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: AppTheme.Size.minTouch, alignment: .leading)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var accessibilityLabel: String {
        let numbers = captionText ?? "No metadata"
        return isMarked ? "\(numbers). Marked for deletion" : numbers
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

    private var captionText: String? {
        guard let metadata = photo.metadata else { return nil }
        return MetadataFormatter.metadataLine([
            metadata.normalizedCameraModel,
            metadata.focalLength.flatMap(MetadataFormatter.focalLength),
            metadata.aperture.flatMap(MetadataFormatter.aperture),
            metadata.shutterSpeedDisplay,
            metadata.iso.flatMap(MetadataFormatter.iso),
            metadata.fileSize.flatMap(MetadataFormatter.fileSize),
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
