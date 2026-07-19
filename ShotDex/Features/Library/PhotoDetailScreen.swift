import AVKit
import Photos
import SwiftUI
import UIKit

/// Anything that can feed the fullscreen viewer with photo pages. Index
/// based so the viewer renders only a small window around the current page
/// — sources may hold the whole library and must not be forced to hand the
/// pager a full metadata array. Full `PhotoMetadata` is fetched per page.
@MainActor
protocol PhotoBrowsingSource: AnyObject {
    var photoCount: Int { get }
    func photoId(at index: Int) -> String?
    /// Full row for the chrome/metadata panel (Library: DAO by primary key;
    /// Albums/On This Day: in-memory array).
    func metadata(for assetId: String) -> PhotoMetadata?
    func asset(for assetId: String) -> PHAsset?
    /// Sources that page (Albums) top up here; full-load sources no-op.
    func loadNextPageIfNeeded(currentIndex: Int)
    func syncFavorite(assetId: String, isFavorite: Bool)
}


/// Fullscreen photo viewer: horizontal paging between photos, pinch/double-tap
/// zoom, swipe-down to dismiss, share, favorite, and the metadata panel.
struct PhotoDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let controller: any PhotoBrowsingSource
    @State var currentIndex: Int

    @State private var isMetadataPresented = false
    @State private var isShareUnavailable = false
    @State private var shareItems: [Any]?
    @State private var dragOffset: CGSize = .zero
    @State private var currentFilename: String?
    /// Fetched lazily per page — reading a resource's file size loads the
    /// asset's original-metadata property set (an on-demand iCloud/main-queue
    /// fetch), too costly for the index pass, fine for one visible photo.
    @State private var currentFileSize: Int?
    /// Full row of the current page, fetched on index change — a computed
    /// lookup would hit the source (Library: a DB read) on every body
    /// evaluation, and the dismiss drag evaluates the body per frame.
    @State private var currentMetadata: PhotoMetadata?
    /// Resolved PHAsset of the current page — feeds the raw-metadata sheet.
    @State private var currentAsset: PHAsset?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // UIKit UIPageViewController — pages are created lazily via its
            // data source, so a library of any size stays cheap and paging is
            // native (a windowed SwiftUI `TabView(.page)` remounted pages on
            // every index change and stuttered/stuck mid-swipe).
            PhotoPager(
                source: controller,
                photoLibrary: photoLibrary,
                currentIndex: $currentIndex,
                onDragProgress: { translationY in
                    dragOffset = CGSize(width: 0, height: max(0, translationY))
                },
                onDragEnded: { shouldDismiss in
                    if shouldDismiss {
                        dismiss()
                    } else {
                        withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                    }
                }
            )
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if let metadata = currentMetadata {
                    infoPanel(metadata)
                    actionBar(metadata)
                }
            }
        }
        .offset(y: max(0, dragOffset.height))
        .scaleEffect(dismissScale)
        .statusBarHidden()
        .sheet(isPresented: $isMetadataPresented) {
            MetadataPanel(asset: currentAsset)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Unable to Share", isPresented: $isShareUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This photo hasn't been downloaded from iCloud yet.")
        }
        .onChange(of: currentIndex) { _, newIndex in
            controller.loadNextPageIfNeeded(currentIndex: newIndex)
            refreshCurrentPhoto()
        }
        .onAppear { refreshCurrentPhoto() }
    }

    /// Re-resolves the current page's full metadata + filename.
    private func refreshCurrentPhoto() {
        guard let assetId = controller.photoId(at: currentIndex) else {
            currentMetadata = nil
            currentFilename = nil
            return
        }
        currentMetadata = controller.metadata(for: assetId)
        currentAsset = controller.asset(for: assetId)
        updateFilename(assetId: assetId)
    }

    // MARK: Chrome

    /// Only the close button sits at the top; the rest of the actions live in
    /// the bottom bar.
    private var topBar: some View {
        HStack {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") {
                dismiss()
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Favorite / Share / Info, pinned to the bottom below the info panel.
    private func actionBar(_ metadata: PhotoMetadata) -> some View {
        HStack(spacing: 16) {
            GlassIconButton(
                systemImage: metadata.isFavorite ? "heart.fill" : "heart",
                accessibilityLabel: metadata.isFavorite ? "Unfavorite" : "Favorite"
            ) {
                toggleFavorite(metadata)
            }
            GlassIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share") {
                share(metadata)
            }
            GlassIconButton(systemImage: "info.circle", accessibilityLabel: "Info") {
                isMetadataPresented = true
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    private func infoPanel(_ metadata: PhotoMetadata) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let filename = currentFilename {
                        Text(filename)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                    }
                    if let badge = formatBadge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer()
                }
                if let gear = FormatUtils.metadataLine([
                    metadata.normalizedCameraModel,
                    metadata.normalizedLensModel,
                ]) {
                    Text(gear)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let exposure = FormatUtils.metadataLine([
                    metadata.iso.flatMap(FormatUtils.iso),
                    metadata.focalLength.flatMap(FormatUtils.focalLength),
                    metadata.aperture.flatMap(FormatUtils.aperture),
                    metadata.shutterSpeedDisplay,
                    currentFileSize.flatMap(FormatUtils.fileSize),
                ]) {
                    Text(exposure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .onTapGesture { isMetadataPresented = true }
    }

    private var formatBadge: String? {
        guard let filename = currentFilename?.uppercased() else { return nil }
        for suffix in ["RAF", "CR2", "CR3", "NEF", "ARW", "ORF", "RW2", "DNG"] where filename.hasSuffix(suffix) {
            return "RAW"
        }
        if filename.hasSuffix("HEIC") || filename.hasSuffix("HEIF") { return "HEIC" }
        if filename.hasSuffix("JPG") || filename.hasSuffix("JPEG") { return "JPG" }
        if filename.hasSuffix("PNG") { return "PNG" }
        return nil
    }

    // MARK: Dismiss gesture

    private var dismissScale: CGFloat {
        let progress = min(max(dragOffset.height, 0) / 600, 1)
        return 1 - progress * 0.15
    }

    // MARK: Actions

    private func toggleFavorite(_ metadata: PhotoMetadata) {
        guard let asset = controller.asset(for: metadata.assetId) else { return }
        let newValue = !metadata.isFavorite
        Task {
            do {
                try await photoLibrary.setFavorite(newValue, for: asset)
                controller.syncFavorite(assetId: metadata.assetId, isFavorite: newValue)
                currentMetadata?.isFavorite = newValue
            } catch {
                // PhotoKit change failed (e.g. user denied) — leave state as is.
            }
        }
    }

    private func share(_ metadata: PhotoMetadata) {
        guard let asset = controller.asset(for: metadata.assetId) else {
            isShareUnavailable = true
            return
        }
        if asset.mediaType == .video {
            shareVideo(asset)
        } else {
            shareImage(asset)
        }
    }

    private func shareImage(_ asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            Task { @MainActor in
                guard let data else {
                    isShareUnavailable = true
                    return
                }
                presentShareSheet(items: [data as Any], filename: currentFilename)
            }
        }
    }

    private func shareVideo(_ asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            Task { @MainActor in
                guard let urlAsset = avAsset as? AVURLAsset else {
                    isShareUnavailable = true
                    return
                }
                presentShareSheet(items: [urlAsset.url], filename: currentFilename)
            }
        }
    }

    private func presentShareSheet(items: [Any], filename: String?) {
        guard let scene = UIApplication.shared.connectedScenes
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

    private func updateFilename(assetId: String) {
        currentFilename = nil
        currentFileSize = nil
        guard let asset = controller.asset(for: assetId) else { return }
        // The filename is cheap, but reading `fileSize` (KVC) can trigger an
        // on-demand iCloud metadata fetch — resolve both off the main thread
        // and apply only if the user hasn't paged away in the meantime.
        Task.detached(priority: .userInitiated) {
            let resources = PHAssetResource.assetResources(for: asset)
            let filename = resources.first?.originalFilename
            let resource = ExifService.photoResource(among: resources)
            let size = (resource?.value(forKey: "fileSize") as? NSNumber)?.intValue
            await MainActor.run {
                guard controller.photoId(at: currentIndex) == assetId else { return }
                currentFilename = filename
                currentFileSize = size
            }
        }
    }
}

/// One page of the detail pager: the zoomable full image, or an AVPlayer for
/// videos. Resolves its own asset from the source on appear and keeps it in
/// `@State`, so the parent's per-frame body evaluations (dismiss drag) never
/// re-fetch anything.
struct PhotoDetailPage: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let source: any PhotoBrowsingSource
    let index: Int
    /// Bubbled up by the pager so it can suppress swipe-down-dismiss while
    /// the image is zoomed in.
    var onZoomChange: ((CGFloat) -> Void)?

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isVideo = false
    /// A degraded preview is showing while the full-resolution asset still
    /// streams from iCloud — drives the download badge.
    @State private var isFetchingFullImage = false
    @State private var downloadProgress: Double = 0

    var body: some View {
        Group {
            if isVideo {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView().tint(.white)
                }
            } else if let image {
                ZoomableImageView(image: image, onZoomChange: onZoomChange)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if isFetchingFullImage {
                downloadBadge
                    .padding(.top, 60)
            }
        }
        .onAppear { load() }
        .onDisappear { player?.pause() }
    }

    /// iCloud download indicator: shown while only a degraded preview is on
    /// screen and the full image is still streaming.
    private var downloadBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.caption.weight(.semibold))
            if downloadProgress > 0, downloadProgress < 1 {
                Text("\(Int(downloadProgress * 100))%")
                    .font(.caption.weight(.medium).monospacedDigit())
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .transition(.opacity)
    }

    private func load() {
        guard let assetId = source.photoId(at: index),
              let asset = source.asset(for: assetId)
        else { return }
        if asset.mediaType == .video {
            isVideo = true
            loadVideo(asset)
        } else {
            loadImage(asset)
        }
    }

    private func loadImage(_ asset: PHAsset) {
        guard image == nil else { return }
        let scale = UIScreen.main.scale
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * scale,
            height: UIScreen.main.bounds.height * scale
        )
        isFetchingFullImage = true
        _ = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: targetSize,
            progress: { value in downloadProgress = value }
        ) { result, isDegraded in
            if let result {
                image = result
            }
            // Full-resolution frame arrived (or the request produced no more
            // callbacks) — drop the badge.
            if !isDegraded {
                withAnimation(.easeOut(duration: 0.2)) { isFetchingFullImage = false }
            }
        }
    }

    private func loadVideo(_ asset: PHAsset) {
        guard player == nil else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            guard let item else { return }
            Task { @MainActor in
                player = AVPlayer(playerItem: item)
            }
        }
    }
}

// MARK: - UIKit pager

/// Horizontal photo pager backed by `UIPageViewController`. Pages are built
/// on demand through its data source, so the source may hold the whole
/// library without materializing every page. Also owns a downward
/// pan-to-dismiss recognizer that yields to horizontal paging and to a
/// zoomed-in image.
private struct PhotoPager: UIViewControllerRepresentable {
    let source: any PhotoBrowsingSource
    let photoLibrary: PhotoLibraryService
    @Binding var currentIndex: Int
    let onDragProgress: (CGFloat) -> Void
    let onDragEnded: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        pager.view.backgroundColor = .clear
        if let initial = context.coordinator.makePage(at: currentIndex) {
            pager.setViewControllers([initial], direction: .forward, animated: false)
        }
        context.coordinator.installDismissPan(on: pager)
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncIfNeeded(pager, to: currentIndex)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource,
        UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: PhotoPager
        /// Zoom scale of the page currently on screen — dismiss is disabled
        /// while zoomed so panning moves the image instead.
        private var currentZoom: CGFloat = 1

        init(_ parent: PhotoPager) {
            self.parent = parent
        }

        /// Builds a page for `index`, or nil when out of range (stops paging
        /// at the library ends).
        func makePage(at index: Int) -> PhotoPageHost? {
            guard index >= 0, index < parent.source.photoCount else { return nil }
            let page = PhotoDetailPage(
                source: parent.source,
                index: index,
                onZoomChange: { [weak self] scale in self?.currentZoom = scale }
            )
            .environment(parent.photoLibrary)
            let host = PhotoPageHost(index: index, rootView: AnyView(page))
            host.view.backgroundColor = .clear
            return host
        }

        // MARK: Data source

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let host = viewController as? PhotoPageHost else { return nil }
            return makePage(at: host.index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let host = viewController as? PhotoPageHost else { return nil }
            return makePage(at: host.index + 1)
        }

        // MARK: Delegate

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed,
                  let host = pageViewController.viewControllers?.first as? PhotoPageHost
            else { return }
            currentZoom = 1
            parent.currentIndex = host.index
            parent.source.loadNextPageIfNeeded(currentIndex: host.index)
        }

        /// Re-seats the pager when `currentIndex` is driven from outside (the
        /// binding no longer matches the displayed page).
        func syncIfNeeded(_ pager: UIPageViewController, to index: Int) {
            let shown = (pager.viewControllers?.first as? PhotoPageHost)?.index
            guard shown != index, let page = makePage(at: index) else { return }
            let direction: UIPageViewController.NavigationDirection =
                (shown ?? index) <= index ? .forward : .reverse
            currentZoom = 1
            pager.setViewControllers([page], direction: direction, animated: false)
        }

        // MARK: Dismiss pan

        func installDismissPan(on pager: UIPageViewController) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
            pan.delegate = self
            pager.view.addGestureRecognizer(pan)
        }

        @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .changed:
                parent.onDragProgress(max(0, translation.y))
            case .ended, .cancelled:
                let velocity = gesture.velocity(in: gesture.view)
                parent.onDragEnded(translation.y > 140 || velocity.y > 900)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            guard currentZoom <= 1.01 else { return false }
            let velocity = pan.velocity(in: pan.view)
            // Downward, vertical-dominant only — horizontal swipes stay with
            // the page view's own paging pan.
            return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

/// Hosting controller that remembers its page index so the pager's data
/// source can walk to neighbours.
private final class PhotoPageHost: UIHostingController<AnyView> {
    let index: Int

    init(index: Int, rootView: AnyView) {
        self.index = index
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
