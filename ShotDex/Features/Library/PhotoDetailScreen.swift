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
    /// Current position of a photo by its stable id. Viewers open by identity
    /// (not a captured position) so a deletion that shifts the array can't
    /// desync the opened page.
    func index(of assetId: String) -> Int?
    /// Full row for the chrome/metadata panel (Library: DAO by primary key;
    /// Albums/On This Day: in-memory array).
    func metadata(for assetId: String) -> PhotoMetadata?
    func asset(for assetId: String) -> PHAsset?
    /// Sources that page (Albums) top up here; full-load sources no-op.
    func loadNextPageIfNeeded(currentIndex: Int)
    func syncFavorite(assetId: String, isFavorite: Bool)
    /// Deletes one asset via PhotoKit (which shows its own system confirm) and
    /// prunes it from the source. Throws `PHPhotosError.userCancelled` if the
    /// user cancels the system dialog.
    func deleteAsset(id: String) async throws
    /// After a full-size image finishes downloading from iCloud, read its EXIF
    /// and persist it so a `pendingICloud`/`error`/unindexed row fills in and
    /// never needs re-downloading. Returns the refreshed row (for the info
    /// panel), or nil when nothing changed.
    func refreshMetadataAfterDownload(assetId: String) async -> PhotoMetadata?
}


/// Presentation target for the fullscreen viewer, captured at tap time. Holds
/// the stable id (for `fullScreenCover(item:)` identity) plus the starting
/// index — resolved once, so an in-viewer deletion that prunes the source can't
/// blank the cover by re-resolving a now-missing id every parent render.
struct PhotoViewerTarget: Identifiable, Equatable {
    let id: String
    let startIndex: Int
}

/// Fullscreen photo viewer: horizontal paging between photos, pinch/double-tap
/// zoom, swipe-down to dismiss, share, favorite, and the metadata panel.
struct PhotoDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppDependencies.self) private var dependencies

    let controller: any PhotoBrowsingSource
    @State var currentIndex: Int

    /// Bumped after an in-viewer deletion prunes the source; forces the pager
    /// to rebuild the current page even when the (clamped) index is unchanged.
    @State private var reseatToken = 0
    @State private var isMetadataPresented = false
    /// True while the current image is pinch/double-tap zoomed in — hides all
    /// chrome (top bar, action buttons, info panel) so nothing overlaps the photo.
    @State private var isZoomed = false
    /// Measured height of the bottom info panel. Fed to the pager so a video's
    /// native transport controls get bottom room and render ABOVE the panel.
    @State private var bottomChromeHeight: CGFloat = 0
    /// Bottom safe-area inset (home indicator). The panel lives inside the safe
    /// area, so the video inset must clear this gap too, not just the panel.
    @State private var safeAreaBottom: CGFloat = 0
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
    /// iCloud download state of the *current* page, bubbled up from the pages so
    /// the ring can live in the info panel (pages report their own index; only
    /// the visible page's updates are kept).
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    /// True once a download has shown zero progress for a full stall window —
    /// iCloud isn't serving (device-level issue); the ring flips to a warning
    /// badge so the user doesn't stare at an endless spinner.
    @State private var downloadStalled = false
    @State private var stallWatchTask: Task<Void, Never>?
    /// Latest (progress, downloading) reported per page index. Pages preload
    /// off-screen and report BEFORE they become current, so the visible ring
    /// reads the current index out of here — otherwise a swiped-to page whose
    /// download already stalled would show no ring/stall at all (its one report
    /// fired while it wasn't current). Pruned to a small window around current.
    @State private var pageDownload: [Int: (progress: Double, downloading: Bool)] = [:]

    /// No-progress window before a download is declared stalled.
    private static let stallWindow: Duration = .seconds(15)

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
                reseatToken: reseatToken,
                videoBottomInset: bottomChromeHeight > 0 ? bottomChromeHeight + safeAreaBottom : 0,
                onDragProgress: { translationY in
                    dragOffset = CGSize(width: 0, height: max(0, translationY))
                },
                onDragEnded: { shouldDismiss in
                    if shouldDismiss {
                        dismiss()
                    } else {
                        withAnimation(.spring(duration: 0.3)) { dragOffset = .zero }
                    }
                },
                onZoomChange: { scale in
                    withAnimation(.easeInOut(duration: 0.2)) { isZoomed = scale > 1.01 }
                },
                onSwipeUp: { isMetadataPresented = true },
                onDownloadStateChange: { index, progress, downloading in
                    // An active iCloud stream keeps extending the indexing
                    // pause, so long downloads never lose the bandwidth.
                    dependencies.indexInteractionGate.touch()
                    // Record every page (incl. off-screen preloads); the ring
                    // reflects whichever page is current.
                    recordDownloadState(index: index, progress: progress, downloading: downloading)
                },
                onMetadataRefresh: { index in
                    guard index == currentIndex else { return }
                    refreshRowMetadata(index: index)
                }
            )
            .ignoresSafeArea()

            if !isZoomed {
                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        GlassIconButton(systemImage: "xmark", accessibilityLabel: "Close") {
                            dismiss()
                        }
                        if let metadata = currentMetadata {
                            infoPanel(metadata)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    Spacer()
                    if let metadata = currentMetadata {
                        actionBar(metadata)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ChromeHeightKey.self,
                                        value: proxy.size.height
                                    )
                                }
                            )
                    }
                }
                .transition(.opacity)
            }
        }
        .background(
            // A GeometryReader that ignores the safe area reports the inset it
            // covers — how we read the home-indicator gap without disturbing the
            // safe-area-respecting chrome above.
            GeometryReader { proxy in
                Color.clear.preference(key: SafeAreaBottomKey.self, value: proxy.safeAreaInsets.bottom)
            }
            .ignoresSafeArea()
        )
        .onPreferenceChange(SafeAreaBottomKey.self) { safeAreaBottom = $0 }
        .onPreferenceChange(ChromeHeightKey.self) { bottomChromeHeight = $0 }
        .offset(y: max(0, dragOffset.height))
        .scaleEffect(dismissScale)
        .preferredColorScheme(.dark)
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
            dependencies.indexInteractionGate.touch()
            controller.loadNextPageIfNeeded(currentIndex: newIndex)
            refreshCurrentPhoto()
        }
        .onAppear {
            // Viewer open = interactive demand: the index pipeline stops
            // spawning iCloud reads so this photo's download comes through
            // in seconds instead of queueing behind the EXIF pass.
            dependencies.indexInteractionGate.beginInteraction()
            refreshCurrentPhoto()
        }
        .onDisappear {
            dependencies.indexInteractionGate.endInteraction()
            stallWatchTask?.cancel()
            stallWatchTask = nil
        }
    }

    /// Arms a one-shot watch while a download reports zero progress; a full
    /// `stallWindow` without a byte flips `downloadStalled`. Any progress,
    /// completion, or page change disarms it.
    private func updateStallWatch(progress: Double, downloading: Bool) {
        if downloading && progress == 0 {
            guard stallWatchTask == nil else { return }
            stallWatchTask = Task {
                try? await Task.sleep(for: Self.stallWindow)
                guard !Task.isCancelled else { return }
                if isDownloading && downloadProgress == 0 {
                    withAnimation(.easeInOut(duration: 0.2)) { downloadStalled = true }
                }
            }
        } else {
            stallWatchTask?.cancel()
            stallWatchTask = nil
            if downloadStalled {
                withAnimation(.easeInOut(duration: 0.2)) { downloadStalled = false }
            }
        }
    }

    /// Re-resolves the current page's full metadata + filename.
    private func refreshCurrentPhoto() {
        // Reset the displayed ring, then re-apply the now-current page's state
        // — a swiped-to page reported its download BEFORE it became current
        // (off-screen preload), so its progress/stall lives in `pageDownload`.
        downloadStalled = false
        // The pager resets its own zoom on a page change but doesn't report it;
        // clear the chrome-hiding flag so a new page always shows the chrome.
        isZoomed = false
        stallWatchTask?.cancel()
        stallWatchTask = nil
        applyCurrentDownloadState()
        guard let assetId = controller.photoId(at: currentIndex) else {
            currentMetadata = nil
            currentFilename = nil
            return
        }
        currentMetadata = controller.metadata(for: assetId)
        currentAsset = controller.asset(for: assetId)
        updateFilename(assetId: assetId)
    }

    /// Stores a page's download report and, when it is the visible page,
    /// reflects it in the ring. Keeps only a small window around the current
    /// index so the map can't grow across a large library.
    private func recordDownloadState(index: Int, progress: Double, downloading: Bool) {
        pageDownload[index] = (progress, downloading)
        pageDownload = pageDownload.filter { abs($0.key - currentIndex) <= 2 }
        if index == currentIndex {
            applyCurrentDownloadState()
        }
    }

    /// Drives the ring/stall watch from the current page's recorded state.
    private func applyCurrentDownloadState() {
        let state = pageDownload[currentIndex] ?? (progress: 0, downloading: false)
        downloadProgress = state.progress
        withAnimation(.easeInOut(duration: 0.2)) { isDownloading = state.downloading }
        updateStallWatch(progress: state.progress, downloading: state.downloading)
    }

    /// Streams + persists the row's EXIF so an incomplete row fills in (and
    /// never re-streams). Fired when the page appears — decoupled from the
    /// deferred full-resolution image download. Skips rows already fully
    /// indexed, and applies the refreshed row only if the user hasn't paged away.
    private func refreshRowMetadata(index: Int) {
        guard currentMetadata?.resolvedExifStatus != .indexed,
              let assetId = controller.photoId(at: index)
        else { return }
        Task {
            guard let updated = await controller.refreshMetadataAfterDownload(assetId: assetId) else { return }
            guard controller.photoId(at: currentIndex) == assetId else { return }
            currentMetadata = updated
        }
    }

    // MARK: Chrome

    /// Favorite / Share / Info / Delete, centered along the bottom. Its height
    /// is measured (`ChromeHeightKey`) and fed to a video as a bottom inset so
    /// the transport controls render above the bar.
    private func actionBar(_ metadata: PhotoMetadata) -> some View {
        HStack(spacing: 28) {
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
            GlassIconButton(systemImage: "trash", accessibilityLabel: "Delete") {
                deleteCurrentPhoto()
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func infoPanel(_ metadata: PhotoMetadata) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let date = metadata.creationDateValue {
                        Text(date.formatted(.dateTime.day().month().year().hour().minute()))
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
                    if downloadStalled {
                        Image(systemName: "exclamationmark.icloud")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.orange)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("iCloud download stalled")
                    } else if isDownloading {
                        // iOS-style "downloading from iCloud" ring around a cloud
                        // glyph, top-right of the info panel.
                        ICloudDownloadRing(progress: downloadProgress)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("Downloading from iCloud")
                    }
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
                if downloadStalled {
                    Text("iCloud isn't responding — check iCloud Photos in Settings or the Photos app.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)
        }
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

    /// Deletes the current photo. PhotoKit shows its own system confirm; on a
    /// successful delete the source shrinks, so the pager is re-seated to the
    /// same (clamped) index — showing the next photo, iOS-Photos style — or the
    /// viewer dismisses when the album empties.
    private func deleteCurrentPhoto() {
        guard let assetId = controller.photoId(at: currentIndex) else { return }
        Task {
            do {
                try await controller.deleteAsset(id: assetId)
            } catch {
                // User cancelled the system confirm, or the change failed —
                // leave the viewer as is.
                return
            }
            let count = controller.photoCount
            guard count > 0 else {
                dismiss()
                return
            }
            currentIndex = min(currentIndex, count - 1)
            reseatToken += 1
            refreshCurrentPhoto()
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

/// Reports the bottom info panel's measured height up to `PhotoDetailScreen`,
/// which forwards it to the pager as a video's bottom inset.
private struct ChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Bottom safe-area inset, read via an ignore-safe-area GeometryReader.
private struct SafeAreaBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// iOS-style "downloading from iCloud" indicator: a cloud glyph wrapped by a
/// circular progress ring. Determinate once the download reports a fraction,
/// otherwise a continuously rotating arc.
private struct ICloudDownloadRing: View {
    /// 0…1; treated as indeterminate while it is 0 (or ≥ 1).
    let progress: Double
    @State private var spin = false

    private var isDeterminate: Bool { progress > 0 && progress < 1 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
            if isDeterminate {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: progress)
            } else {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            }
            Image(systemName: "icloud")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 22, height: 22)
        .onAppear { spin = true }
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
    /// Bottom room reserved on a video so its native transport controls render
    /// above the info panel instead of behind it. 0 for photos (full-bleed zoom).
    var videoBottomInset: CGFloat = 0
    /// Bubbled up by the pager so it can suppress swipe-down-dismiss while
    /// the image is zoomed in.
    var onZoomChange: ((CGFloat) -> Void)?
    /// Reports this page's iCloud download state — (index, progress 0…1,
    /// isDownloading) — so the info-panel ring reflects the visible page.
    var onDownloadStateChange: ((Int, Double, Bool) -> Void)?
    /// Fires on appear so the row's EXIF can be streamed + persisted. Decoupled
    /// from the (deferred) full-resolution image download — the metadata read is
    /// a cheap ~KB header stream, must not wait on a multi-MB original.
    var onMetadataRefresh: ((Int) -> Void)?

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isVideo = false
    @State private var asset: PHAsset?
    /// Set once the full-resolution original request has been fired (first
    /// zoom-in), so a later zoom doesn't kick off a second download.
    @State private var didRequestFullResolution = false
    /// In-flight screen-sized display request — cancelled when the page scrolls
    /// away so preloaded neighbours don't keep downloading and starve the
    /// visible page's download of bandwidth.
    @State private var requestId: PHImageRequestID?
    /// In-flight full-original request (zoom-to-pixel-peep) — cancelled with the
    /// page too; it pulls the multi-MB original so leaving mid-download must not
    /// keep it running.
    @State private var fullResRequestId: PHImageRequestID?
    /// In-flight best-local-rendition request (sharp placeholder while the
    /// iCloud derivative streams) — fired once per page, cancelled with it.
    @State private var localBestRequestId: PHImageRequestID?
    @State private var didRequestLocalBest = false

    var body: some View {
        Group {
            if isVideo {
                if let player {
                    // Native AVKit transport (play / scrubber / mute / AirPlay).
                    // Bottom inset keeps its control bar above the info panel.
                    VideoPlayer(player: player)
                        .padding(.bottom, videoBottomInset)
                } else {
                    ProgressView().tint(.white)
                }
            } else if let image {
                ZoomableImageView(image: image, onZoomChange: handleZoom)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { load() }
        .onDisappear {
            player?.pause()
            if let requestId {
                photoLibrary.cancelThumbnailRequest(requestId)
            }
            if let fullResRequestId {
                photoLibrary.cancelThumbnailRequest(fullResRequestId)
            }
            if let localBestRequestId {
                photoLibrary.cancelThumbnailRequest(localBestRequestId)
            }
            requestId = nil
            fullResRequestId = nil
            localBestRequestId = nil
        }
    }

    private func load() {
        guard let assetId = source.photoId(at: index),
              let asset = source.asset(for: assetId)
        else { return }
        self.asset = asset
        if asset.mediaType == .video {
            isVideo = true
            loadVideo(asset)
        } else {
            loadDisplayImage(asset)
            // Fill EXIF for incomplete rows now — independent of the image
            // download (streams only the ~KB metadata header).
            onMetadataRefresh?(index)
        }
    }

    private var targetSize: CGSize {
        let scale = UIScreen.main.scale
        return CGSize(
            width: UIScreen.main.bounds.width * scale,
            height: UIScreen.main.bounds.height * scale
        )
    }

    /// The viewable image: a screen-sized derivative (`allowNetwork: true`).
    /// iCloud serves a screen-sized rendition here — a few hundred KB, fast —
    /// NOT the multi-MB original (that only downloads on zoom / share). This is
    /// how Photos loads a sharp full-screen image quickly even when the original
    /// is offloaded. `.opportunistic` paints a local low-res placeholder first,
    /// then swaps in the sharp derivative; the ring shows while it streams.
    private func loadDisplayImage(_ asset: PHAsset) {
        guard image == nil else { return }
        // 1. Sharp local rendition immediately, independent of the network
        //    callback — the main image whenever iCloud is slow/unreachable.
        //    (The `.opportunistic` degraded delivery is just the blurry cached
        //    grid thumbnail, and it may never arrive when the daemon is stuck.)
        loadLocalBest(asset)
        // 2. Mark downloading up front so the ring + stall watch arm even if no
        //    network callback ever fires; a local-only asset clears it below.
        onDownloadStateChange?(index, 0, true)
        // 3. Screen-sized iCloud derivative — upgrades the image when it lands.
        requestId = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: targetSize,
            allowNetwork: true,
            progress: { value in onDownloadStateChange?(index, value, true) }
        ) { result, isDegraded in
            if let result { image = result }
            if isDegraded {
                onDownloadStateChange?(index, 0, true)
            } else {
                onDownloadStateChange?(index, 1, false)
                requestId = nil
            }
        }
    }

    /// Sharp no-network placeholder: the device-sized rendition "Optimize
    /// iPhone Storage" keeps locally. Applied only while the network final is
    /// still pending and only when it beats the current image's resolution —
    /// never downgrades.
    private func loadLocalBest(_ asset: PHAsset) {
        guard !didRequestLocalBest else { return }
        didRequestLocalBest = true
        localBestRequestId = photoLibrary.requestBestLocalImage(for: asset, targetSize: targetSize) { result in
            localBestRequestId = nil
            guard let result, requestId != nil else { return }
            let currentPixelWidth = (image?.size.width ?? 0) * (image?.scale ?? 1)
            if result.size.width * result.scale > currentPixelWidth {
                image = result
            }
        }
    }

    /// Upgrades to the full original (`PHImageManagerMaximumSize`) for
    /// pixel-peeping when the user zooms in. Pulls the multi-MB original from
    /// iCloud (ring shows). Idempotent — only the first zoom downloads.
    private func loadFullResolution() {
        guard !didRequestFullResolution, let asset else { return }
        didRequestFullResolution = true
        fullResRequestId = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            allowNetwork: true,
            progress: { value in onDownloadStateChange?(index, value, true) }
        ) { result, isDegraded in
            if let result { image = result }
            if isDegraded {
                onDownloadStateChange?(index, 0, true)
            } else {
                onDownloadStateChange?(index, 1, false)
                fullResRequestId = nil
            }
        }
    }

    /// Forwards the zoom scale to the pager (to suppress swipe-down-dismiss) and
    /// upgrades to the full original on the first zoom-in.
    private func handleZoom(_ scale: CGFloat) {
        onZoomChange?(scale)
        if scale > 1.01 { loadFullResolution() }
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
    /// Rebuild trigger: when this changes the current page is re-seated even if
    /// `currentIndex` is unchanged (after an in-viewer deletion shifts content).
    let reseatToken: Int
    /// Bottom room reserved on video pages (action-bar height).
    let videoBottomInset: CGFloat
    let onDragProgress: (CGFloat) -> Void
    let onDragEnded: (Bool) -> Void
    /// Zoom scale of the current page — drives chrome hide-on-zoom.
    let onZoomChange: (CGFloat) -> Void
    /// Upward swipe on the photo — opens the full-metadata sheet.
    let onSwipeUp: () -> Void
    let onDownloadStateChange: (Int, Double, Bool) -> Void
    let onMetadataRefresh: (Int) -> Void

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
        context.coordinator.installGestures(on: pager)
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reseatIfNeeded(pager, token: reseatToken, to: currentIndex)
        context.coordinator.syncIfNeeded(pager, to: currentIndex)
        context.coordinator.applyVideoInsetIfNeeded(pager)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource,
        UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: PhotoPager
        /// Zoom scale of the page currently on screen — dismiss is disabled
        /// while zoomed so panning moves the image instead.
        private var currentZoom: CGFloat = 1
        /// Video bottom inset last pushed into the displayed page.
        private var appliedVideoInset: CGFloat = 0
        /// Last reseat token acted on — starts at 0 to match the initial
        /// `reseatToken`, so the first update never forces a rebuild.
        private var appliedReseatToken = 0

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
                videoBottomInset: parent.videoBottomInset,
                onZoomChange: { [weak self] scale in
                    self?.currentZoom = scale
                    self?.parent.onZoomChange(scale)
                },
                onDownloadStateChange: { [weak self] idx, progress, downloading in
                    self?.parent.onDownloadStateChange(idx, progress, downloading)
                },
                onMetadataRefresh: { [weak self] idx in
                    self?.parent.onMetadataRefresh(idx)
                }
            )
            .environment(parent.photoLibrary)
            let isVideo = parent.source.photoId(at: index)
                .flatMap { parent.source.asset(for: $0) }?.mediaType == .video
            let host = PhotoPageHost(index: index, isVideo: isVideo, rootView: AnyView(page))
            host.view.backgroundColor = .clear
            return host
        }

        /// The panel height is 0 until the chrome lays out, so a video page
        /// first built with inset 0 would sit behind the panel. Rebuild just the
        /// current page (only when it's a video) once the real inset lands.
        func applyVideoInsetIfNeeded(_ pager: UIPageViewController) {
            guard parent.videoBottomInset != appliedVideoInset else { return }
            appliedVideoInset = parent.videoBottomInset
            guard let host = pager.viewControllers?.first as? PhotoPageHost,
                  host.isVideo,
                  let rebuilt = makePage(at: host.index)
            else { return }
            pager.setViewControllers([rebuilt], direction: .forward, animated: false)
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

        /// Forces a rebuild of the current page after an in-viewer deletion.
        /// The item now at `index` is different content (the old array shifted),
        /// so the cached page host must be replaced even when `index` is
        /// unchanged — which `syncIfNeeded` alone would skip.
        func reseatIfNeeded(_ pager: UIPageViewController, token: Int, to index: Int) {
            guard token != appliedReseatToken else { return }
            appliedReseatToken = token
            guard let page = makePage(at: index) else { return }
            currentZoom = 1
            pager.setViewControllers([page], direction: .forward, animated: false)
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

        // MARK: Gestures

        func installGestures(on pager: UIPageViewController) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
            pan.delegate = self
            pager.view.addGestureRecognizer(pan)

            // Upward swipe opens the full-metadata sheet (same as the "i"
            // button). Discrete, so it doesn't fight the downward dismiss pan.
            let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp))
            swipeUp.direction = .up
            swipeUp.delegate = self
            pager.view.addGestureRecognizer(swipeUp)
        }

        @objc private func handleSwipeUp() {
            parent.onSwipeUp()
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
            // Swipe-up (open metadata) only when not zoomed — a zoomed pan
            // still moves the image.
            if gestureRecognizer is UISwipeGestureRecognizer {
                return currentZoom <= 1.01
            }
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
    let isVideo: Bool

    init(index: Int, isVideo: Bool, rootView: AnyView) {
        self.index = index
        self.isVideo = isVideo
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
