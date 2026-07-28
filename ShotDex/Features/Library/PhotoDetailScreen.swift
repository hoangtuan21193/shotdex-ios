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
    /// Writable user album that owns the opened grid, if any. New copies are
    /// added back to this collection after Edit/Compress.
    var sourceAlbum: PHAssetCollection? { get }
    func photoId(at index: Int) -> String?
    /// Current position of a photo by its stable id. Viewers open by identity
    /// (not a captured position) so a deletion that shifts the array can't
    /// desync the opened page.
    func index(of assetId: String) -> Int?
    /// Full row for the chrome/metadata panel (Library: a DB lookup by primary key;
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

extension PhotoBrowsingSource {
    var sourceAlbum: PHAssetCollection? { nil }
}

/// Presentation target for the fullscreen viewer, captured at tap time. Holds
/// the stable id (for `fullScreenCover(item:)` identity) plus the starting
/// index — resolved once, so an in-viewer deletion that prunes the source can't
/// blank the cover by re-resolving a now-missing id every parent render.
struct PhotoViewerTarget: Identifiable, Equatable {
    let id: String
    let startIndex: Int
}

private struct PhotoDetailActionTarget: Identifiable {
    let id: String
    let asset: PHAsset
    let sourceAlbum: PHAssetCollection?
}

/// Fullscreen photo viewer: horizontal paging between photos, pinch/double-tap
/// zoom, swipe-down to dismiss, share, favorite, and the metadata panel.
struct PhotoDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: any PhotoBrowsingSource
    @State var currentIndex: Int

    /// Bumped after an in-viewer deletion prunes the source; forces the pager
    /// to rebuild the current page even when the (clamped) index is unchanged.
    @State private var reseatToken = 0
    @State private var isMetadataPresented = false
    @State private var editorTarget: PhotoDetailActionTarget?
    @State private var compressionTarget: PhotoDetailActionTarget?
    /// True while the current image is pinch/double-tap zoomed in — hides all
    /// chrome (top bar, action buttons, info panel) so nothing overlaps the photo.
    @State private var isZoomed = false
    /// Portrait immersive playback: hides viewer chrome without requesting an
    /// interface rotation.
    @State private var isVideoFullscreen = false
    /// Shared visibility for every video overlay: transport, top info and bottom
    /// actions disappear together after idle playback.
    @State private var isVideoChromeVisible = true
    @State private var isCurrentVideoPlaying = false
    @State private var videoChromeHideTask: Task<Void, Never>?
    /// Measured height of the bottom action bar. Fed to the pager so a video's
    /// custom transport renders above the bar.
    @State private var bottomChromeHeight: CGFloat = 0
    /// Bottom safe-area inset (home indicator). The panel lives inside the safe
    /// area, so the video inset must clear this gap too, not just the panel.
    @State private var safeAreaBottom: CGFloat = 0
    @State private var safeAreaTop: CGFloat = 0
    /// Measured width of the info panel's content frame. The summary lines are
    /// fitted to it, so the panel never truncates a value mid-word. Measured
    /// once via `measureWidth` rather than a per-frame GeometryReader — the
    /// dismiss drag re-evaluates this body every frame.
    @State private var panelContentWidth: CGFloat = 0
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
    @State private var isDownloadStalled = false
    @State private var stallWatchTask: Task<Void, Never>?
    /// Latest explicit full-original download state per page index. Local-only
    /// paging reports false to clear stale state; zoom downloads are isolated
    /// by index so their ring never leaks onto the next page.
    @State private var pageDownload: [Int: (progress: Double, downloading: Bool)] = [:]

    /// No-progress window before a download is declared stalled.
    private static let stallWindow: Duration = .seconds(15)
    /// Glass buttons can render beyond their 52 pt layout bounds. Keep the
    /// transport one spacing tier above that visual bloom.
    private static let videoActionBarClearance: CGFloat = 40
    private static let estimatedActionBarHeight: CGFloat = 64
    private static let videoChromeIdleDelay: Duration = .seconds(3)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // UIKit UIPageViewController — pages are created lazily via its
            // data source, so a library of any size stays cheap and paging is
            // native (a windowed SwiftUI `TabView(.page)` remounted pages on
            // every index change and stuttered/stuck mid-swipe).
            PhotoPager(
                source: model,
                photoLibrary: photoLibrary,
                currentIndex: $currentIndex,
                reseatToken: reseatToken,
                videoBottomInset:
                    max(bottomChromeHeight, Self.estimatedActionBarHeight)
                    + safeAreaBottom
                    + Self.videoActionBarClearance,
                videoFullscreenEdgeInset: max(24, max(safeAreaTop, safeAreaBottom)),
                isVideoFullscreen: isVideoFullscreen,
                isVideoChromeVisible: isVideoChromeVisible,
                onVideoFullscreenChange: { fullscreen in
                    if reduceMotion {
                        isVideoFullscreen = fullscreen
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isVideoFullscreen = fullscreen
                        }
                    }
                },
                onVideoPlaybackChange: { index, playing in
                    guard index == currentIndex else { return }
                    handleVideoPlaybackChange(playing)
                },
                onVideoInteraction: showVideoChrome,
                onVideoTap: toggleVideoChrome,
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
                    // Only an explicit zoom/original stream needs to extend the
                    // indexing pause. Local paging reports false merely to
                    // clear stale state for that page.
                    if downloading {
                        dependencies.indexInteractionGate.touch()
                    }
                    recordDownloadState(index: index, progress: progress, downloading: downloading)
                },
                onMetadataRefresh: { index in
                    guard index == currentIndex else { return }
                    refreshRowMetadata(index: index)
                }
            )
            .ignoresSafeArea()

            if showsViewerChrome {
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
                Color.clear
                    .preference(key: SafeAreaBottomKey.self, value: proxy.safeAreaInsets.bottom)
                    .preference(key: SafeAreaTopKey.self, value: proxy.safeAreaInsets.top)
            }
            .ignoresSafeArea()
        )
        .onPreferenceChange(SafeAreaBottomKey.self) { safeAreaBottom = $0 }
        .onPreferenceChange(SafeAreaTopKey.self) { safeAreaTop = $0 }
        .onPreferenceChange(ChromeHeightKey.self) { bottomChromeHeight = $0 }
        .offset(y: max(0, dragOffset.height))
        .scaleEffect(dismissScale)
        .preferredColorScheme(.dark)
        .statusBarHidden(shouldHideStatusBar)
        .sheet(isPresented: $isMetadataPresented) {
            MetadataPanel(
                asset: currentAsset,
                indexedMetadata: currentMetadata
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $editorTarget) { target in
            PhotoEditorScreen(
                asset: target.asset,
                sourceAlbum: target.sourceAlbum
            )
        }
        .fullScreenCover(item: $compressionTarget) { target in
            CompressionScreen(
                assets: [target.asset],
                sourceAlbum: target.sourceAlbum
            )
        }
        .alert("Unable to Share", isPresented: $isShareUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This photo hasn't been downloaded from iCloud yet.")
        }
        .onChange(of: currentIndex) { _, newIndex in
            dependencies.indexInteractionGate.touch()
            model.loadNextPageIfNeeded(currentIndex: newIndex)
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
            videoChromeHideTask?.cancel()
            videoChromeHideTask = nil
        }
    }

    /// Arms a one-shot watch while a download reports zero progress; a full
    /// `stallWindow` without a byte flips `isDownloadStalled`. Any progress,
    /// completion, or page change disarms it.
    private func updateStallWatch(progress: Double, downloading: Bool) {
        if downloading && progress == 0 {
            guard stallWatchTask == nil else { return }
            stallWatchTask = Task {
                try? await Task.sleep(for: Self.stallWindow)
                guard !Task.isCancelled else { return }
                if isDownloading && downloadProgress == 0 {
                    withAnimation(.easeInOut(duration: 0.2)) { isDownloadStalled = true }
                }
            }
        } else {
            stallWatchTask?.cancel()
            stallWatchTask = nil
            if isDownloadStalled {
                withAnimation(.easeInOut(duration: 0.2)) { isDownloadStalled = false }
            }
        }
    }

    /// Re-resolves the current page's full metadata + filename.
    private func refreshCurrentPhoto() {
        // Reset the displayed ring, then re-apply the now-current page's state
        // — a swiped-to page reported its download BEFORE it became current
        // (off-screen preload), so its progress/stall lives in `pageDownload`.
        isDownloadStalled = false
        // The pager resets its own zoom on a page change but doesn't report it;
        // clear the chrome-hiding flag so a new page always shows the chrome.
        isZoomed = false
        isVideoFullscreen = false
        isVideoChromeVisible = true
        isCurrentVideoPlaying = false
        videoChromeHideTask?.cancel()
        videoChromeHideTask = nil
        stallWatchTask?.cancel()
        stallWatchTask = nil
        applyCurrentDownloadState()
        guard let assetId = model.photoId(at: currentIndex) else {
            currentMetadata = nil
            currentFilename = nil
            return
        }
        currentMetadata = model.metadata(for: assetId)
        currentAsset = model.asset(for: assetId)
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
              let assetId = model.photoId(at: index)
        else { return }
        Task {
            guard let updated = await model.refreshMetadataAfterDownload(assetId: assetId) else { return }
            guard model.photoId(at: currentIndex) == assetId else { return }
            currentMetadata = updated
        }
    }

    // MARK: Chrome

    private var isCurrentVideo: Bool {
        currentAsset?.mediaType == .video
    }

    private var showsViewerChrome: Bool {
        !isZoomed
            && !isVideoFullscreen
            && (!isCurrentVideo || isVideoChromeVisible)
    }

    private var shouldHideStatusBar: Bool {
        isVideoFullscreen || (isCurrentVideo && !isVideoChromeVisible)
    }

    /// Photos-style three-zone action row: Share is isolated at the leading
    /// edge, Delete at the trailing edge, and non-destructive actions share one
    /// centered glass capsule. The exact center stays fixed on every width.
    private func actionBar(_ metadata: PhotoMetadata) -> some View {
        ZStack {
            HStack {
                GlassIconButton(
                    systemImage: "square.and.arrow.up",
                    accessibilityLabel: "Share"
                ) {
                    showVideoChrome()
                    share(metadata)
                }
                Spacer()
                GlassIconButton(systemImage: "trash", accessibilityLabel: "Delete") {
                    showVideoChrome()
                    deleteCurrentPhoto()
                }
            }

            GlassPanel(cornerRadius: 28) {
                HStack(spacing: 8) {
                    actionBarCenterButton(
                        systemImage: metadata.isFavorite ? "heart.fill" : "heart",
                        accessibilityLabel: metadata.isFavorite ? "Unfavorite" : "Favorite"
                    ) {
                        showVideoChrome()
                        toggleFavorite(metadata)
                    }
                    actionBarCenterButton(
                        systemImage: "info.circle",
                        accessibilityLabel: "Info"
                    ) {
                        showVideoChrome()
                        isMetadataPresented = true
                    }
                    if !isCurrentVideo, let currentAsset {
                        actionBarCenterButton(
                            systemImage: "slider.horizontal.3",
                            accessibilityLabel: "Edit"
                        ) {
                            editorTarget = PhotoDetailActionTarget(
                                id: currentAsset.localIdentifier,
                                asset: currentAsset,
                                sourceAlbum: model.sourceAlbum
                            )
                        }
                        actionBarCenterButton(
                            systemImage: "arrow.down.right.and.arrow.up.left",
                            accessibilityLabel: "Compress"
                        ) {
                            compressionTarget = PhotoDetailActionTarget(
                                id: currentAsset.localIdentifier,
                                asset: currentAsset,
                                sourceAlbum: model.sourceAlbum
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 56)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func actionBarCenterButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func handleVideoPlaybackChange(_ playing: Bool) {
        guard isCurrentVideo else { return }
        isCurrentVideoPlaying = playing
        if playing {
            showVideoChrome()
        } else {
            videoChromeHideTask?.cancel()
            videoChromeHideTask = nil
            setVideoChromeVisible(true)
        }
    }

    private func showVideoChrome() {
        guard isCurrentVideo else { return }
        videoChromeHideTask?.cancel()
        videoChromeHideTask = nil
        setVideoChromeVisible(true)
        guard isCurrentVideoPlaying else { return }
        videoChromeHideTask = Task { @MainActor in
            try? await Task.sleep(for: Self.videoChromeIdleDelay)
            guard !Task.isCancelled, isCurrentVideo, isCurrentVideoPlaying else { return }
            setVideoChromeVisible(false)
            videoChromeHideTask = nil
        }
    }

    private func toggleVideoChrome() {
        guard isCurrentVideo else { return }
        if isVideoChromeVisible {
            guard isCurrentVideoPlaying else { return }
            videoChromeHideTask?.cancel()
            videoChromeHideTask = nil
            setVideoChromeVisible(false)
        } else {
            showVideoChrome()
        }
    }

    private func setVideoChromeVisible(_ visible: Bool) {
        if reduceMotion {
            isVideoChromeVisible = visible
        } else {
            withAnimation(.easeInOut(duration: visible ? 0.2 : 0.15)) {
                isVideoChromeVisible = visible
            }
        }
    }

    /// Top-left chrome panel: capture date/time on line 1, camera + exposure on
    /// line 2, fitted to the width left over beside the Close button.
    /// `PhotoInfoPanelSummary` owns which fields survive that width — see its
    /// doc comment for why the old single `metadataLine` truncated the exposure
    /// values away.
    private func infoPanel(_ metadata: PhotoMetadata) -> some View {
        let summary = panelSummary(metadata)
        // A Button, not `onTapGesture`: the panel is the second way into the
        // Photo Info sheet and has to be reachable by VoiceOver/Switch Control.
        return Button {
            isMetadataPresented = true
        } label: {
            GlassPanel(cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(summary.titleLine)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.92)
                        if let badge = formatBadge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer()
                        if isDownloadStalled {
                            Image(systemName: "exclamationmark.icloud")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.orange)
                                .transition(.scale.combined(with: .opacity))
                        } else if isDownloading {
                            // iOS-style "downloading from iCloud" ring around a cloud
                            // glyph, top-right of the info panel.
                            ICloudDownloadRing(progress: downloadProgress)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    // Accessibility Dynamic Type can't fit a second line inside
                    // the 52 pt panel without truncating mid-value; the full data
                    // is one tap away in the sheet, so the line is dropped.
                    if !dynamicTypeSize.isAccessibilitySize, let detail = summary.detailLine {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.92)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
                .measureWidth(into: $panelContentWidth)
            }
        }
        .buttonStyle(.plain)
        // One element that announces every field, including the ones the
        // measured width dropped from the visible lines.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityPanelLabel(summary))
        .accessibilityHint("Shows all photo info")
    }

    private func panelSummary(_ metadata: PhotoMetadata) -> PhotoInfoPanelSummary {
        PhotoInfoPanelSummary(
            metadata: metadata,
            fileSize: currentFileSize ?? metadata.fileSize,
            fallbackTitle: currentFilename,
            availableWidth: Double(max(0, panelContentWidth - Self.panelTextInsets)),
            measureDetail: { Self.width(of: $0, style: .caption2) }
        )
    }

    /// Announces every field even when the visible lines dropped some, plus
    /// whatever the trailing badge and glyph are saying visually.
    private func accessibilityPanelLabel(_ summary: PhotoInfoPanelSummary) -> String {
        var parts = [summary.accessibilityText]
        if let badge = formatBadge { parts.append(badge) }
        if isDownloadStalled {
            parts.append(String(localized: "iCloud download stalled"))
        } else if isDownloading {
            parts.append(String(localized: "Downloading from iCloud"))
        }
        return parts.joined(separator: ", ")
    }

    /// Horizontal padding inside the panel, subtracted from the measured frame.
    private static let panelTextInsets: CGFloat = 24

    /// Text width at the current Dynamic Type size. `preferredFont` already
    /// tracks the user's size, so the fit follows Dynamic Type without the
    /// summary having to know about it.
    private static func width(of text: String, style: UIFont.TextStyle) -> Double {
        let font = UIFont.preferredFont(forTextStyle: style)
        return (text as NSString).size(withAttributes: [.font: font]).width
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
        guard let asset = model.asset(for: metadata.assetId) else { return }
        let newValue = !metadata.isFavorite
        Task {
            do {
                try await photoLibrary.setFavorite(newValue, for: asset)
                model.syncFavorite(assetId: metadata.assetId, isFavorite: newValue)
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
        guard let assetId = model.photoId(at: currentIndex) else { return }
        Task {
            do {
                try await model.deleteAsset(id: assetId)
            } catch {
                // User cancelled the system confirm, or the change failed —
                // leave the viewer as is.
                return
            }
            let count = model.photoCount
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
        guard let asset = model.asset(for: metadata.assetId) else {
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
        PhotoShareSheet.present(items: items)
    }

    private func updateFilename(assetId: String) {
        currentFilename = currentMetadata?.originalFilename
        currentFileSize = currentMetadata?.fileSize
        let needsFilename = currentFilename == nil
        let needsFileSize = currentFileSize == nil
        guard needsFilename || needsFileSize else { return }
        guard let asset = model.asset(for: assetId) else { return }
        // The filename is cheap, but reading `fileSize` (KVC) can trigger an
        // on-demand iCloud metadata fetch — resolve both off the main thread
        // only when the indexed row is missing a value, and apply only if the
        // user hasn't paged away in the meantime.
        Task.detached(priority: .userInitiated) {
            let resources = PHAssetResource.assetResources(for: asset)
            let filename = needsFilename ? resources.first?.originalFilename : nil
            let size: Int? = needsFileSize
                ? ExifReader.photoResource(among: resources).flatMap {
                    ($0.value(forKey: "fileSize") as? NSNumber)?.intValue
                }
                : nil
            await MainActor.run {
                guard model.photoId(at: currentIndex) == assetId else { return }
                if currentFilename == nil {
                    currentFilename = filename
                }
                if currentFileSize == nil {
                    currentFileSize = size
                }
            }
        }
    }
}

/// Reports the bottom action bar's measured height up to `PhotoDetailScreen`,
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

private struct SafeAreaTopKey: PreferenceKey {
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

/// The system route picker keeps AirPlay / external-screen behavior native
/// while allowing the rest of the transport to use a Photos-style layout.
private struct VideoRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.activeTintColor = .white
        picker.tintColor = .white
        picker.prioritizesVideoDevices = true
        picker.accessibilityLabel = "AirPlay"
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        picker.activeTintColor = .white
        picker.tintColor = .white
    }
}

/// YouTube-style fullscreen while the app remains portrait-only. The player
/// content rotates inside its own bounds, so Rotation Lock never participates.
private struct VideoFullscreenLayout: ViewModifier {
    let isFullscreen: Bool
    let containerSize: CGSize

    func body(content: Content) -> some View {
        if isFullscreen, containerSize.height > containerSize.width {
            content
                .frame(width: containerSize.height, height: containerSize.width)
                .rotationEffect(.degrees(90))
                .position(x: containerSize.width / 2, y: containerSize.height / 2)
        } else {
            content
                .frame(width: containerSize.width, height: containerSize.height)
        }
    }
}

/// Photos-style video view and bottom transport. The controls intentionally
/// live only at the bottom: the viewer's Close + info chrome owns the top row,
/// so mute and AirPlay can never be covered by it.
private struct DetailVideoPlayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: VideoPlaybackModel
    let isActive: Bool
    let bottomInset: CGFloat
    let fullscreenEdgeInset: CGFloat
    let isFullscreen: Bool
    let isChromeVisible: Bool
    let onFullscreenChange: (Bool) -> Void
    let onPlaybackChange: (Bool) -> Void
    let onInteraction: () -> Void
    let onContentTap: () -> Void
    let onZoomChange: (CGFloat) -> Void

    /// Bumped on every ±10 s seek so the matching centre button re-runs its
    /// bounce. A plain counter rather than a timed overlay: `symbolEffect`
    /// restarts on each new value, which is what makes rapid taps read as
    /// separate skips.
    @State private var skipBackPulse = 0
    @State private var skipForwardPulse = 0
    /// Delays the spinner so a locally cached clip never flashes one — same
    /// grace the image path uses.
    @State private var showBufferingIndicator = false
    @State private var bufferingIndicatorTask: Task<Void, Never>?
    @State private var frameSaveTask: Task<Void, Never>?
    /// Mirrored from the video view own zoom so the centre cluster can get out of
    /// the way. The host's `isZoomed` only drives the viewer chrome, not this.
    @State private var isContentZoomed = false
    /// Whether the opening autoplay window is over. Opening a clip is for watching
    /// it, not for looking at buttons, so during that first window only the bottom
    /// panel appears. Resets per page — this view is rebuilt for each one.
    @State private var hasLeftOpeningAutoplay = false
    /// The user just pressed ▶ on the centre cluster, so chrome has to go away the
    /// moment playback actually starts.
    @State private var hasRequestedHideOnPlay = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let player = model.player {
                    ZoomableVideoView(
                        model: model,
                        player: player,
                        // Fullscreen re-lays-out the video view; a zoom carried
                        // across would frame the wrong region.
                        resetToken: isFullscreen ? 1 : 0,
                        onZoomChange: { scale in
                            isContentZoomed = scale > 1.01
                            onZoomChange(scale)
                        },
                        onSingleTap: handleSingleTap,
                        onDoubleTap: { location, size in
                            handleDoubleTap(
                                at: location,
                                contentSize: size,
                                containerSize: proxy.size
                            )
                        }
                    )
                } else {
                    Color.black
                }

                // Below `statusOverlay`: the spinner, the iCloud ring and the
                // failure card all share this centre, and a clip that cannot
                // play must not have transport sitting on top of the reason.
                //
                // Opacity rather than `if` + transition: visibility is derived
                // from `model.isPlaying`, which changes outside any
                // `withAnimation`, so an insert/remove transition would pop.
                centerTransport
                    .opacity(isCenterTransportVisible ? 1 : 0)
                    // Invisible must also mean untappable, otherwise the play
                    // button swallows the tap that is supposed to pause.
                    .allowsHitTesting(isCenterTransportVisible)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.18),
                        value: isCenterTransportVisible
                    )

                statusOverlay

                if isActive && isChromeVisible, model.player != nil {
                    VStack(spacing: 0) {
                        Spacer()
                        transport
                    }
                    .padding(
                        .horizontal,
                        isFullscreen ? fullscreenEdgeInset + 8 : 16
                    )
                    .padding(.bottom, isFullscreen ? 16 : bottomInset + 8)
                    .transition(.opacity)
                }
            }
            .modifier(
                VideoFullscreenLayout(
                    isFullscreen: isFullscreen,
                    containerSize: proxy.size
                )
            )
        }
        .onAppear {
            if isActive {
                model.play()
            }
            syncBufferingIndicator(for: model.phase)
        }
        .onChange(of: isActive) { _, active in
            if active {
                model.play()
            } else {
                model.pause()
            }
        }
        .onChange(of: isChromeVisible) { _, visible in
            if !visible {
                hasLeftOpeningAutoplay = true
            }
        }
        .onChange(of: model.isPlaying) { _, playing in
            if !playing {
                hasLeftOpeningAutoplay = true
            }
            onPlaybackChange(playing)
            // Pressing ▶ has to clear the screen at once — the button must not sit
            // under the finger for another 3 s. Reuse the host's toggle path: the
            // call above already set its `isCurrentVideoPlaying` synchronously, so
            // the toggle resolves to *hide* rather than show.
            if playing, hasRequestedHideOnPlay {
                hasRequestedHideOnPlay = false
                onContentTap()
            }
        }
        .onChange(of: model.phase) { _, phase in
            syncBufferingIndicator(for: phase)
        }
        .onChange(of: model.frameSaveOutcome) { _, outcome in
            scheduleFrameSaveDismissal(outcome)
        }
        .onDisappear {
            model.pause()
            bufferingIndicatorTask?.cancel()
            frameSaveTask?.cancel()
        }
    }

    // MARK: Centre transport

    /// One control set with the bottom panel: panel shown means this is shown,
    /// panel hidden means this is hidden. Gating on `!isPlaying` instead meant a
    /// tap during playback raised only the panel while the centre cluster stayed
    /// hidden — nothing to press.
    ///
    /// `hasLeftOpeningAutoplay || !isPlaying` are two opposite exceptions: during
    /// the opening autoplay window (playing, chrome up, flag not yet set) the
    /// middle of the frame stays clear, while a `.ready` clip that is *not*
    /// playing must show the cluster even before the flag is set — otherwise a clip
    /// that failed to autoplay would have no play button at all.
    ///
    /// Still hidden on its own whenever something else owns the middle of the
    /// frame: the phase overlays, the transient frame-save badge, and a zoomed
    /// video — three 56–68 pt circles sit exactly where the inner pan gesture is
    /// needed.
    private var isCenterTransportVisible: Bool {
        isActive
            && isChromeVisible
            && model.player != nil
            && model.phase.isReady
            && (hasLeftOpeningAutoplay || !model.isPlaying)
            && !isContentZoomed
            && !model.isSavingFrame
            && model.frameSaveOutcome == nil
    }

    /// The primary controls sit over the middle of the picture, Photos-style,
    /// because that is where the thumb already is — a 44 pt play button wedged
    /// between the panel edge and the elapsed label was both small and covered by
    /// the hand reaching for it. Dimmed circles rather than a `GlassPanel`: this
    /// floats directly on the video, not on a panel.
    private var centerTransport: some View {
        HStack(spacing: 28) {
            centerButton(
                systemImage: "gobackward.10",
                accessibilityLabel: "Skip back 10 seconds",
                diameter: 56,
                glyphSize: 22,
                pulse: skipBackPulse
            ) {
                handleSkip(isLeading: true)
            }

            centerButton(
                systemImage: model.isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: model.isPlaying ? "Pause" : "Play",
                diameter: 68,
                glyphSize: 30,
                pulse: nil
            ) {
                onInteraction()
                if !model.isPlaying {
                    hasRequestedHideOnPlay = true
                }
                model.togglePlayPause()
            }

            centerButton(
                systemImage: "goforward.10",
                accessibilityLabel: "Skip forward 10 seconds",
                diameter: 56,
                glyphSize: 22,
                pulse: skipForwardPulse
            ) {
                handleSkip(isLeading: false)
            }
        }
    }

    private func centerButton(
        systemImage: String,
        accessibilityLabel: String,
        diameter: CGFloat,
        glyphSize: CGFloat,
        pulse: Int?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.black.opacity(0.28))
                centerGlyph(systemImage, size: glyphSize, pulse: pulse)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func centerGlyph(
        _ systemImage: String,
        size: CGFloat,
        pulse: Int?
    ) -> some View {
        let glyph = Image(systemName: systemImage)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
        if let pulse, !reduceMotion {
            glyph.symbolEffect(.bounce, options: .nonRepeating.speed(1.6), value: pulse)
        } else {
            glyph
        }
    }

    /// Single entry point for ±10 s, so the centre buttons and the double-tap
    /// produce identical state — including the bounce.
    private func handleSkip(isLeading: Bool) {
        onInteraction()
        model.skip(by: isLeading
            ? -VideoPlaybackModel.skipInterval
            : VideoPlaybackModel.skipInterval)
        if isLeading {
            skipBackPulse += 1
        } else {
            skipForwardPulse += 1
        }
    }

    /// Two rows in one glass panel: play/pause + scrubber, then six secondary
    /// controls spread across the full width. Moving the *primary* play/pause out
    /// to `centerTransport` is what left room for loop and save-frame to become
    /// permanent buttons instead of entries in an `ellipsis` menu, where a toggle
    /// could not show its own state.
    private var transport: some View {
        GlassPanel(cornerRadius: 28) {
            VStack(spacing: 0) {
                timelineRow
                controlsRow
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private var timelineRow: some View {
        HStack(spacing: 4) {
            // Deliberately a second play/pause, duplicating the centre cluster:
            // the cluster steps aside while the video is zoomed, and this row is
            // the one place still on screen then. It does *not* set
            // `hasRequestedHideOnPlay` — the finger here is not covering the picture,
            // and hiding the panel would pull the scrubber out from under it.
            transportButton(
                systemImage: model.isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: model.isPlaying ? "Pause" : "Play"
            ) {
                onInteraction()
                model.togglePlayPause()
            }

            timeLabel(MetadataFormatter.duration(model.displayTime))

            Slider(
                value: Binding(
                    get: { model.displayTime },
                    set: { model.updateScrub($0) }
                ),
                in: 0...model.timelineUpperBound,
                onEditingChanged: scrub
            )
            .tint(.white)
            .accessibilityLabel("Video progress")
            .accessibilityValue(progressAccessibilityValue)

            timeLabel(remainingLabel)
        }
        .frame(height: 44)
    }

    /// `Spacer`s rather than fixed spacing: six 44 pt targets spread evenly
    /// across whatever width the panel has. The narrowest case (375 pt phone,
    /// minus the viewer's and the panel's padding) still leaves ~55 pt to
    /// distribute, so nothing gets squeezed.
    private var controlsRow: some View {
        HStack(spacing: 0) {
            rateMenu

            Spacer(minLength: 0)

            transportButton(
                systemImage: model.isMuted
                    ? "speaker.slash.fill"
                    : "speaker.wave.2.fill",
                accessibilityLabel: model.isMuted ? "Unmute" : "Mute"
            ) {
                onInteraction()
                model.isMuted.toggle()
            }

            Spacer(minLength: 0)

            VideoRoutePicker()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

            Spacer(minLength: 0)

            loopButton

            Spacer(minLength: 0)

            transportButton(
                systemImage: "camera.viewfinder",
                accessibilityLabel: "Save Frame to Photos"
            ) {
                onInteraction()
                model.saveCurrentFrame()
            }
            .disabled(model.isSavingFrame)

            Spacer(minLength: 0)

            transportButton(
                systemImage: isFullscreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: isFullscreen
                    ? "Exit full screen"
                    : "Enter full screen"
            ) {
                onInteraction()
                onFullscreenChange(!isFullscreen)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 44)
    }

    /// Two distinct glyphs, both plain white, rather than one glyph plus a
    /// highlight: on a bright frame a background disc or an opacity shift does not
    /// read as on-vs-off.
    ///
    /// The slash is drawn by hand because SF Symbols has no `repeat.slash` — and
    /// with no such symbol, `.symbolVariant(.slash)` is a no-op. The dark capsule
    /// underneath is the knockout Apple's own `.slash` variants use; without it
    /// the white bar disappears wherever it crosses the glyph's own strokes.
    private var loopButton: some View {
        Button {
            onInteraction()
            model.isLooping.toggle()
        } label: {
            Image(systemName: "repeat")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .overlay {
                    if !model.isLooping {
                        ZStack {
                            Capsule()
                                .fill(.black.opacity(0.65))
                                .frame(width: 5, height: 26)
                            Capsule()
                                .fill(.white)
                                .frame(width: 2, height: 26)
                        }
                        // Lower-left to upper-right, matching `speaker.slash`
                        // and the rest of the family.
                        .rotationEffect(.degrees(45))
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Loop")
        .accessibilityValue(model.isLooping ? "On" : "Off")
    }

    private var rateMenu: some View {
        Menu {
            Picker("Playback Speed", selection: rateSelection) {
                ForEach(VideoPlaybackModel.supportedRates, id: \.self) { value in
                    Text(Self.rateLabel(value)).tag(value)
                }
            }
        } label: {
            Text(Self.rateLabel(model.rate))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(Self.rateLabel(model.rate))
        .simultaneousGesture(TapGesture().onEnded { onInteraction() })
    }

    private var rateSelection: Binding<Double> {
        Binding(
            get: { model.rate },
            set: { newValue in
                onInteraction()
                model.rate = newValue
            }
        )
    }

    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            // Fixed width so the scrubber does not shift when the digit count
            // changes (0:09 → 0:10, or crossing a minute). Wide enough for
            // "-12:34" — play/pause shares this row, so the slider cannot spare
            // any more.
            .frame(width: 44)
    }

    /// Photos-style trailing label: time left, not total length. Blank until
    /// AVFoundation resolves an iCloud item's duration — a wrong number there is
    /// worse than none.
    private var remainingLabel: String {
        guard let remaining = VideoTransportMath.remainingSeconds(
            current: model.displayTime,
            duration: model.duration
        ) else { return "--:--" }
        return "-" + MetadataFormatter.duration(remaining)
    }

    private static func rateLabel(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f×", value)
            : String(format: "%.1f×", value)
    }

    // MARK: Status overlay

    /// Always on top of the video, independent of chrome visibility: a clip
    /// that cannot play must say so even after the transport has faded out.
    @ViewBuilder
    private var statusOverlay: some View {
        switch model.phase {
        case .downloading(let progress):
            VStack(spacing: 10) {
                ICloudDownloadRing(progress: progress)
                    .scaleEffect(1.6)
                    .tint(.white)
                Text("Downloading from iCloud")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(20)
            .transition(.opacity)

        case .buffering:
            if showBufferingIndicator {
                ProgressView()
                    .tint(.white)
                    .transition(.opacity)
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Button {
                    onInteraction()
                    model.retry()
                } label: {
                    Text("Retry")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule().fill(.white.opacity(0.18))
                )
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.black.opacity(0.55))
            )
            .transition(.opacity)

        case .idle, .ready:
            if let outcome = model.frameSaveOutcome {
                frameSaveBadge(outcome)
            } else if model.isSavingFrame {
                frameSaveBadge(nil)
            }
        }
    }

    private func frameSaveBadge(_ outcome: VideoFrameSaveOutcome?) -> some View {
        VStack(spacing: 8) {
            switch outcome {
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                Text("Frame Saved")
                    .font(.footnote.weight(.semibold))
            case .failed(let message):
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 26))
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            case nil:
                ProgressView()
                    .tint(.white)
                Text("Saving Frame…")
                    .font(.footnote)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.55))
        )
        .transition(.opacity)
    }

    // MARK: Content taps

    /// While the clip runs, a tap anywhere pauses — and pausing pins chrome open,
    /// so that same tap is also how the whole control set comes back. The previous
    /// version only accepted a 160 pt box in the middle, an invisible boundary:
    /// tap outside it and nothing happened, with no way to know why.
    ///
    /// Paused, the tap falls through to the chrome toggle as before.
    private func handleSingleTap() {
        if model.isPlaying {
            onInteraction()
            model.pause()
        } else {
            onContentTap()
        }
    }

    private func handleDoubleTap(
        at location: CGPoint,
        contentSize: CGSize,
        containerSize: CGSize
    ) {
        // In immersive fullscreen the video view is rotated 90° inside its own
        // bounds (`VideoFullscreenLayout`), so the tap arrives in pre-rotation
        // coordinates: the screen's left/right halves are the video view's
        // *vertical* axis. Whether that rotation happened is a property of the
        // container, but the midpoint to compare against belongs to the video view.
        let isRotated = isFullscreen && containerSize.height > containerSize.width
        let isLeading = isRotated
            ? location.y > contentSize.height / 2
            : location.x < contentSize.width / 2
        handleSkip(isLeading: isLeading)
    }

    // MARK: Overlay timing

    private func syncBufferingIndicator(for phase: VideoPlaybackPhase) {
        bufferingIndicatorTask?.cancel()
        guard phase == .buffering else {
            showBufferingIndicator = false
            return
        }
        bufferingIndicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, model.phase == .buffering else { return }
            showBufferingIndicator = true
        }
    }

    private func scheduleFrameSaveDismissal(_ outcome: VideoFrameSaveOutcome?) {
        frameSaveTask?.cancel()
        guard outcome != nil else { return }
        frameSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(outcome == .saved ? 1.4 : 2.6))
            guard !Task.isCancelled else { return }
            model.clearFrameSaveOutcome()
        }
    }

    private var progressAccessibilityValue: String {
        let total = model.duration
        guard total.isFinite, total > 0 else {
            return MetadataFormatter.duration(model.displayTime)
        }
        return "\(MetadataFormatter.duration(model.displayTime)) of \(MetadataFormatter.duration(total))"
    }

    private func transportButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func scrub(_ editing: Bool) {
        onInteraction()
        if editing {
            model.beginScrub()
        } else {
            model.endScrub()
        }
    }
}

/// Per-host visibility signal. UIPageViewController may construct/load neighbour
/// pages before they are visible; only the active host may start a network
/// screen-derivative request.
@MainActor
@Observable
final class DetailPageLoadState {
    var isActive = false
    var videoBottomInset: CGFloat = 0
    var videoFullscreenEdgeInset: CGFloat = 0
    var isVideoFullscreen = false
    var isVideoChromeVisible = true
}

/// One page of the detail pager: the zoomable full image, or an AVPlayer for
/// videos. Resolves its own asset from the source on appear and keeps it in
/// `@State`, so the parent's per-frame body evaluations (dismiss drag) never
/// re-fetch anything.
struct PhotoDetailPage: View {
    /// Image callbacks can finish out of order. Their quality must only move
    /// upward: PhotoKit may upscale a soft local rendition to the requested
    /// pixel dimensions, so comparing UIImage width/height cannot tell whether
    /// it is sharper than a network-final rendition.
    private enum ImageQuality: Int {
        case none
        case thumbnail
        case local
        case localOriginal
        case displayFinal
        case original
    }

    @Environment(PhotoLibraryService.self) private var photoLibrary

    let source: any PhotoBrowsingSource
    let index: Int
    let loadState: DetailPageLoadState
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
    /// Toggles portrait immersive playback without changing orientation.
    var onVideoFullscreenChange: ((Bool) -> Void)?
    /// Keeps outer viewer chrome synchronized with the active player's state.
    var onVideoPlaybackChange: ((Bool) -> Void)?
    var onVideoInteraction: (() -> Void)?
    var onVideoTap: (() -> Void)?

    @State private var image: UIImage?
    @State private var imageQuality: ImageQuality = .none
    /// Owns the player, its readiness state machine and the PhotoKit video
    /// request. Created per page identity, torn down on disappear.
    @State private var videoModel = VideoPlaybackModel()
    @State private var isVideo = false
    @State private var asset: PHAsset?
    /// Set once the full-resolution original request has been fired (first
    /// zoom-in), so a later zoom doesn't kick off a second download.
    @State private var hasRequestedFullResolution = false
    /// Fast local preview request. Network is always disabled; it bridges the
    /// few milliseconds until the exact best-local rendition arrives.
    @State private var localPreviewRequestId: PHImageRequestID?
    /// High-quality screen-sized derivative. Only the active page owns one;
    /// neighbours stay local-only until paging completes.
    @State private var displayRequestId: PHImageRequestID?
    /// In-flight full-original request (zoom-to-pixel-peep) — cancelled with the
    /// page too; it pulls the multi-MB original so leaving mid-download must not
    /// keep it running.
    @State private var fullResRequestId: PHImageRequestID?
    /// In-flight exact best-local-rendition request, fired once per page.
    @State private var localBestRequestId: PHImageRequestID?
    /// Actual current-version bytes, read only when already on device and
    /// downsampled to screen size with ImageIO.
    @State private var localOriginalRequestId: PHImageRequestID?
    @State private var hasRequestedLocalBest = false
    @State private var hasRetriedDisplayDerivative = false
    /// Avoids a spinner flash while a preheated/local display proxy resolves.
    /// A genuinely unavailable image still gets feedback after a short grace.
    @State private var showLoadingIndicator = false
    @State private var loadingIndicatorTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isVideo {
                // Rendered for every phase, not only once a player exists: the
                // model owns the downloading / buffering / failed states,
                // which is what replaced the old permanently-black screen.
                DetailVideoPlayer(
                    model: videoModel,
                    isActive: loadState.isActive,
                    bottomInset: loadState.videoBottomInset,
                    fullscreenEdgeInset: loadState.videoFullscreenEdgeInset,
                    isFullscreen: loadState.isVideoFullscreen,
                    isChromeVisible: loadState.isVideoChromeVisible,
                    onFullscreenChange: { onVideoFullscreenChange?($0) },
                    onPlaybackChange: { onVideoPlaybackChange?($0) },
                    onInteraction: { onVideoInteraction?() },
                    onContentTap: { onVideoTap?() },
                    // Same channel the image path uses, so suppressing
                    // swipe-to-dismiss / swipe-up-for-metadata while zoomed
                    // needs no video-specific plumbing.
                    onZoomChange: handleZoom
                )
            } else if let image {
                ZoomableImageView(
                    image: image,
                    onZoomStart: loadFullResolution,
                    onZoomChange: handleZoom
                )
            } else {
                ZStack {
                    Color.black
                    if showLoadingIndicator {
                        ProgressView().tint(.white)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // This page is hosted inside its own UIHostingController. Ignoring the
        // safe area only on the outer pager does not propagate into that host,
        // which previously left permanent black status/home-indicator bands
        // even after the image was zoomed.
        .ignoresSafeArea()
        .onAppear { load() }
        .onChange(of: loadState.isActive) { _, active in
            if active {
                if isVideo {
                    // Neighbour pages exist but were never allowed to request
                    // their clip; this is where the visible one starts.
                    videoModel.load()
                    videoModel.play()
                } else {
                    startDisplayUpgradeWhenReady()
                }
            } else {
                videoModel.pause()
                cancelDisplayUpgrade()
            }
        }
        .onDisappear {
            videoModel.tearDown()
            loadingIndicatorTask?.cancel()
            loadingIndicatorTask = nil
            if let localPreviewRequestId {
                photoLibrary.cancelThumbnailRequest(localPreviewRequestId)
            }
            if let displayRequestId {
                photoLibrary.cancelThumbnailRequest(displayRequestId)
            }
            if let fullResRequestId {
                photoLibrary.cancelThumbnailRequest(fullResRequestId)
            }
            if let localBestRequestId {
                photoLibrary.cancelThumbnailRequest(localBestRequestId)
            }
            if let localOriginalRequestId {
                photoLibrary.cancelThumbnailRequest(localOriginalRequestId)
            }
            localPreviewRequestId = nil
            displayRequestId = nil
            fullResRequestId = nil
            localBestRequestId = nil
            localOriginalRequestId = nil
        }
    }

    private func load() {
        guard let assetId = source.photoId(at: index),
              let asset = source.asset(for: assetId)
        else { return }
        self.asset = asset
        if asset.mediaType == .video {
            isVideo = true
            videoModel.configure(
                asset: asset,
                photoLibrary: photoLibrary
            ) { progress, isDownloading in
                onDownloadStateChange?(index, progress, isDownloading)
            }
            // Only the visible page may pull a video. `UIPageViewController`
            // builds neighbours eagerly, and three concurrent whole-clip iCloud
            // downloads starved the one actually on screen — one of the causes
            // of the endless spinner. The initial page is already marked active
            // before `setViewControllers`, so it does start here.
            if loadState.isActive {
                videoModel.load()
            }
        } else {
            scheduleLoadingIndicator()
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

    /// Paging is local-only: paint a cached thumbnail immediately, then replace
    /// it with the exact best-local screen rendition. No iCloud image request
    /// starts just because the user swiped. The full original remains deferred
    /// until an explicit zoom/share action.
    private func loadDisplayImage(_ asset: PHAsset) {
        guard image == nil else { return }
        onDownloadStateChange?(index, 0, false)
        // The cheap local derivative normally hits the grid/PhotoKit cache and
        // prevents a blank frame while the exact local rendition resolves.
        localPreviewRequestId = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            allowNetwork: false
        ) { result in
            // Photos-style offline fallback: even a small local rendition is
            // preferable to a black screen and an endless spinner. It remains
            // the lowest tier, so any better local/display image replaces it.
            if let result {
                promoteImage(result, to: .thumbnail)
            }
            startDisplayUpgradeWhenReady()
        }
        // Exact screen-sized local rendition. PhotoLibraryService also stores
        // the decoded final so swiping back is immediate.
        loadLocalBest(asset)
        loadLocalOriginal(asset)
        startDisplayUpgradeWhenReady()
    }

    /// Sharp no-network display image: the device-sized rendition "Optimize
    /// iPhone Storage" keeps locally. Never downgrades the fast preview.
    private func loadLocalBest(_ asset: PHAsset) {
        guard !hasRequestedLocalBest else { return }
        hasRequestedLocalBest = true
        localBestRequestId = photoLibrary.requestBestLocalImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit
        ) { result in
            localBestRequestId = nil
            if let result {
                promoteImage(result, to: .local)
            }
            startDisplayUpgradeWhenReady()
        }
    }

    /// Guaranteed sharp local path: succeeds only when the current-version
    /// source bytes are already on device, then ImageIO downsamples them to the
    /// display target. An iCloud-only original returns nil without downloading.
    private func loadLocalOriginal(_ asset: PHAsset) {
        guard localOriginalRequestId == nil else { return }
        localOriginalRequestId = photoLibrary.requestLocalOriginalScreenImage(
            for: asset,
            targetSize: targetSize
        ) { result in
            localOriginalRequestId = nil
            if let result {
                promoteImage(result, to: .localOriginal)
            }
        }
    }

    /// Starts the screen-sized upgrade immediately and only for the page
    /// UIPageViewController marked active. Local preview/best-local requests
    /// run in parallel, so an offloaded asset cannot leave the viewer stuck on
    /// its grid thumbnail while a local high-quality request waits or returns
    /// nil.
    private func startDisplayUpgradeWhenReady() {
        guard loadState.isActive, displayRequestId == nil, let asset else { return }
        startDisplayUpgrade(for: asset)
    }

    private func startDisplayUpgrade(for asset: PHAsset) {
        guard loadState.isActive, displayRequestId == nil else { return }
        displayRequestId = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: targetSize,
            allowNetwork: true,
            progress: { value in
                // The local image remains visible. Show network progress only
                // after bytes actually move, never an indeterminate spinner on
                // every page swipe.
                if loadState.isActive, !hasRequestedFullResolution, value > 0 {
                    onDownloadStateChange?(index, value, true)
                }
            }
        ) { result, isDegraded in
            guard loadState.isActive, !hasRequestedFullResolution else { return }
            if !isDegraded {
                let isSharp = result.map { hasDisplayResolution($0, for: asset) } ?? false
                if let result {
                    if isSharp {
                        promoteImage(result, to: .displayFinal)
                    } else if hasUsableDisplayProxy(result, for: asset) {
                        promoteImage(result, to: .local)
                    }
                }
                if isSharp {
                    cancelLocalImageRequests()
                } else if !hasRetriedDisplayDerivative {
                    // Some PhotoKit versions can finish a target-sized request
                    // with a soft local rendition. Retry a larger derivative
                    // before ever considering the multi-megabyte original.
                    hasRetriedDisplayDerivative = true
                    displayRequestId = nil
                    startDisplayUpgrade(
                        for: asset,
                        requestTargetSize: CGSize(
                            width: targetSize.width * 2,
                            height: targetSize.height * 2
                        )
                    )
                    return
                }
                onDownloadStateChange?(index, 1, false)
                displayRequestId = nil
            }
        }
    }

    private func startDisplayUpgrade(
        for asset: PHAsset,
        requestTargetSize: CGSize
    ) {
        guard loadState.isActive, displayRequestId == nil else { return }
        displayRequestId = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: requestTargetSize,
            allowNetwork: true,
            progress: { value in
                if loadState.isActive, !hasRequestedFullResolution, value > 0 {
                    onDownloadStateChange?(index, value, true)
                }
            }
        ) { result, isDegraded in
            guard loadState.isActive, !hasRequestedFullResolution else { return }
            if !isDegraded {
                let isSharp = result.map { hasDisplayResolution($0, for: asset) } ?? false
                if let result {
                    if isSharp {
                        promoteImage(result, to: .displayFinal)
                    } else if hasUsableDisplayProxy(result, for: asset) {
                        promoteImage(result, to: .local)
                    }
                }
                if isSharp {
                    cancelLocalImageRequests()
                }
                onDownloadStateChange?(index, 1, false)
                displayRequestId = nil
            }
        }
    }

    /// Uses actual rendered pixel dimensions, not PhotoKit's degraded flag.
    /// Compare sorted axes so EXIF orientation cannot swap the verdict.
    private func hasDisplayResolution(_ candidate: UIImage, for asset: PHAsset) -> Bool {
        displayResolutionRatio(candidate, for: asset) >= 0.9
    }

    /// A device-local Photos rendition around 1024 px is visually sound as an
    /// immediate full-screen proxy on a ~1290 px display. Reject the much
    /// smaller grid thumbnail, but do not show a spinner merely because a good
    /// local proxy is a little below the final target.
    private func hasUsableDisplayProxy(_ candidate: UIImage, for asset: PHAsset) -> Bool {
        displayResolutionRatio(candidate, for: asset) >= 0.65
    }

    private func displayResolutionRatio(_ candidate: UIImage, for asset: PHAsset) -> CGFloat {
        let sourceWidth = CGFloat(asset.pixelWidth)
        let sourceHeight = CGFloat(asset.pixelHeight)
        guard sourceWidth > 0, sourceHeight > 0 else { return 1 }
        let fitScale = min(
            1,
            min(targetSize.width / sourceWidth, targetSize.height / sourceHeight)
        )
        let expected = [
            sourceWidth * fitScale,
            sourceHeight * fitScale,
        ].sorted()
        let actual = [
            candidate.size.width * candidate.scale,
            candidate.size.height * candidate.scale,
        ].sorted()
        guard expected[0] > 0, expected[1] > 0 else { return 1 }
        return min(actual[0] / expected[0], actual[1] / expected[1])
    }

    private func cancelDisplayUpgrade() {
        if let displayRequestId {
            photoLibrary.cancelThumbnailRequest(displayRequestId)
        }
        displayRequestId = nil
        onDownloadStateChange?(index, 0, false)
    }

    /// Upgrades to the full original (`PHImageManagerMaximumSize`) for
    /// pixel-peeping when the user zooms in. Pulls the multi-MB original from
    /// iCloud (ring shows). Idempotent — only the first zoom downloads.
    private func loadFullResolution() {
        guard !hasRequestedFullResolution, let asset else { return }
        hasRequestedFullResolution = true
        // The original supersedes the screen derivative. Cancel it so a late
        // smaller result cannot overwrite the full-resolution image.
        cancelDisplayUpgrade()
        fullResRequestId = photoLibrary.requestDetailImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            allowNetwork: true,
            progress: { value in
                guard loadState.isActive else { return }
                onDownloadStateChange?(index, value, true)
            }
        ) { result, isDegraded in
            guard loadState.isActive else { return }
            if let result, !isDegraded {
                promoteImage(result, to: .original)
            }
            if isDegraded {
                onDownloadStateChange?(index, 0, true)
            } else {
                cancelLocalImageRequests()
                onDownloadStateChange?(index, 1, false)
                fullResRequestId = nil
            }
        }
    }

    /// Applies an image only when it upgrades the source-quality tier. Within
    /// one tier, a larger decoded result may replace a smaller opportunistic
    /// callback. Lower tiers can never overwrite display-final/original even
    /// if PhotoKit reports larger (upscaled) pixel dimensions.
    private func promoteImage(_ candidate: UIImage, to quality: ImageQuality) {
        guard quality.rawValue >= imageQuality.rawValue else { return }
        if quality == imageQuality, let image {
            let currentPixels = image.size.width * image.scale * image.size.height * image.scale
            let candidatePixels =
                candidate.size.width * candidate.scale * candidate.size.height * candidate.scale
            guard candidatePixels > currentPixels else { return }
        }
        image = candidate
        imageQuality = quality
        showLoadingIndicator = false
        loadingIndicatorTask?.cancel()
        loadingIndicatorTask = nil
    }

    private func scheduleLoadingIndicator() {
        guard image == nil, loadingIndicatorTask == nil else { return }
        showLoadingIndicator = false
        loadingIndicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, image == nil else { return }
            showLoadingIndicator = true
            loadingIndicatorTask = nil
        }
    }

    private func cancelLocalImageRequests() {
        if let localPreviewRequestId {
            photoLibrary.cancelThumbnailRequest(localPreviewRequestId)
        }
        if let localBestRequestId {
            photoLibrary.cancelThumbnailRequest(localBestRequestId)
        }
        if let localOriginalRequestId {
            photoLibrary.cancelThumbnailRequest(localOriginalRequestId)
        }
        localPreviewRequestId = nil
        localBestRequestId = nil
        localOriginalRequestId = nil
    }

    /// Forwards the zoom scale to the pager (to suppress swipe-down-dismiss) and
    /// upgrades to the full original on the first zoom-in.
    private func handleZoom(_ scale: CGFloat) {
        onZoomChange?(scale)
        // Videos have nothing to upgrade to, and an image request here would
        // fight the player's own iCloud progress for the info-panel ring.
        if scale > 1.01, !isVideo { loadFullResolution() }
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
    /// Bottom room reserved on video pages (action bar + home-indicator inset).
    let videoBottomInset: CGFloat
    /// Largest portrait safe-area edge, used after the player rotates in place.
    let videoFullscreenEdgeInset: CGFloat
    let isVideoFullscreen: Bool
    let isVideoChromeVisible: Bool
    let onVideoFullscreenChange: (Bool) -> Void
    let onVideoPlaybackChange: (Int, Bool) -> Void
    let onVideoInteraction: () -> Void
    let onVideoTap: () -> Void
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
        context.coordinator.pager = pager
        if let initial = context.coordinator.makePage(at: currentIndex) {
            // setViewControllers can synchronously trigger the hosted SwiftUI
            // page's onAppear. Mark it active first so that first appearance
            // cannot miss the screen-sized request and remain on a thumbnail.
            initial.loadState.isActive = true
            pager.setViewControllers([initial], direction: .forward, animated: false)
        }
        context.coordinator.preheatDetailImages(around: currentIndex)
        context.coordinator.installGestures(on: pager)
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.reseatIfNeeded(pager, token: reseatToken, to: currentIndex)
        context.coordinator.syncIfNeeded(pager, to: currentIndex)
        context.coordinator.applyVideoChromeState(pager)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource,
        UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: PhotoPager
        weak var pager: UIPageViewController?
        /// Zoom scale of the page currently on screen — dismiss is disabled
        /// while zoomed so panning moves the image instead.
        private var currentZoom: CGFloat = 1
        /// Last reseat token acted on — starts at 0 to match the initial
        /// `reseatToken`, so the first update never forces a rebuild.
        private var appliedReseatToken = 0
        /// Local screen-sized PhotoKit preheat window. Three assets is enough
        /// for the current page plus both swipe directions without creating a
        /// second hidden download queue.
        private var preheatedAssets: [PHAsset] = []

        init(_ parent: PhotoPager) {
            self.parent = parent
        }

        /// Builds a page for `index`, or nil when out of range (stops paging
        /// at the library ends).
        func makePage(at index: Int) -> PhotoPageHost? {
            guard index >= 0, index < parent.source.photoCount else { return nil }
            let loadState = DetailPageLoadState()
            loadState.videoBottomInset = parent.videoBottomInset
            loadState.videoFullscreenEdgeInset = parent.videoFullscreenEdgeInset
            loadState.isVideoFullscreen = parent.isVideoFullscreen
            loadState.isVideoChromeVisible = parent.isVideoChromeVisible
            let page = PhotoDetailPage(
                source: parent.source,
                index: index,
                loadState: loadState,
                onZoomChange: { [weak self] scale in
                    self?.currentZoom = scale
                    self?.parent.onZoomChange(scale)
                },
                onDownloadStateChange: { [weak self] idx, progress, downloading in
                    self?.parent.onDownloadStateChange(idx, progress, downloading)
                },
                onMetadataRefresh: { [weak self] idx in
                    self?.parent.onMetadataRefresh(idx)
                },
                onVideoFullscreenChange: { [weak self] fullscreen in
                    self?.parent.onVideoFullscreenChange(fullscreen)
                },
                onVideoPlaybackChange: { [weak self] playing in
                    self?.parent.onVideoPlaybackChange(index, playing)
                },
                onVideoInteraction: { [weak self] in
                    self?.parent.onVideoInteraction()
                },
                onVideoTap: { [weak self] in
                    self?.parent.onVideoTap()
                }
            )
            .environment(parent.photoLibrary)
            let isVideo = parent.source.photoId(at: index)
                .flatMap { parent.source.asset(for: $0) }?.mediaType == .video
            let host = PhotoPageHost(
                index: index,
                isVideo: isVideo,
                loadState: loadState,
                rootView: AnyView(page)
            )
            host.view.backgroundColor = .clear
            return host
        }

        /// Pushes chrome measurements and fullscreen mode into the existing page
        /// so entering immersive playback never rebuilds or rewinds its player.
        func applyVideoChromeState(_ pager: UIPageViewController) {
            guard let host = pager.viewControllers?.first as? PhotoPageHost,
                  host.isVideo
            else { return }
            host.loadState.videoBottomInset = parent.videoBottomInset
            host.loadState.videoFullscreenEdgeInset = parent.videoFullscreenEdgeInset
            host.loadState.isVideoFullscreen = parent.isVideoFullscreen
            host.loadState.isVideoChromeVisible = parent.isVideoChromeVisible

            updatePageScrollEnabled()
        }

        /// Immersive fullscreen locks paging: a swipe there belongs to the
        /// player, not to the library.
        private func updatePageScrollEnabled() {
            guard let pager else { return }
            let isEnabled = !parent.isVideoFullscreen
            // The UIPageViewController paging scroll view is a direct child.
            for scrollView in pager.view.subviews.compactMap({ $0 as? UIScrollView }) {
                scrollView.isScrollEnabled = isEnabled
            }
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
            for previous in previousViewControllers {
                (previous as? PhotoPageHost)?.loadState.isActive = false
            }
            updatePageScrollEnabled()
            host.loadState.isActive = true
            currentZoom = 1
            parent.currentIndex = host.index
            parent.source.loadNextPageIfNeeded(currentIndex: host.index)
            preheatDetailImages(around: host.index)
        }

        /// Forces a rebuild of the current page after an in-viewer deletion.
        /// The item now at `index` is different content (the old array shifted),
        /// so the cached page host must be replaced even when `index` is
        /// unchanged — which `syncIfNeeded` alone would skip.
        func reseatIfNeeded(_ pager: UIPageViewController, token: Int, to index: Int) {
            guard token != appliedReseatToken else { return }
            appliedReseatToken = token
            guard let page = makePage(at: index) else { return }
            let previous = pager.viewControllers?.compactMap { $0 as? PhotoPageHost } ?? []
            previous.forEach { $0.loadState.isActive = false }
            currentZoom = 1
            page.loadState.isActive = true
            pager.setViewControllers([page], direction: .forward, animated: false)
            updatePageScrollEnabled()
            preheatDetailImages(around: index)
        }

        /// Re-seats the pager when `currentIndex` is driven from outside (the
        /// binding no longer matches the displayed page).
        func syncIfNeeded(_ pager: UIPageViewController, to index: Int) {
            let shown = (pager.viewControllers?.first as? PhotoPageHost)?.index
            guard shown != index, let page = makePage(at: index) else { return }
            let direction: UIPageViewController.NavigationDirection =
                (shown ?? index) <= index ? .forward : .reverse
            let previous = pager.viewControllers?.compactMap { $0 as? PhotoPageHost } ?? []
            previous.forEach { $0.loadState.isActive = false }
            currentZoom = 1
            page.loadState.isActive = true
            pager.setViewControllers([page], direction: direction, animated: false)
            updatePageScrollEnabled()
            preheatDetailImages(around: index)
        }

        func preheatDetailImages(around index: Int) {
            let targetSize = CGSize(
                width: UIScreen.main.bounds.width * UIScreen.main.scale,
                height: UIScreen.main.bounds.height * UIScreen.main.scale
            )
            let newAssets = ((index - 1)...(index + 1)).compactMap { candidate -> PHAsset? in
                guard candidate >= 0, candidate < parent.source.photoCount,
                      let id = parent.source.photoId(at: candidate),
                      let asset = parent.source.asset(for: id),
                      asset.mediaType == .image
                else { return nil }
                return asset
            }
            if !preheatedAssets.isEmpty {
                parent.photoLibrary.stopCachingDetailImages(
                    for: preheatedAssets,
                    targetSize: targetSize
                )
            }
            preheatedAssets = newAssets
            parent.photoLibrary.startCachingDetailImages(
                for: newAssets,
                targetSize: targetSize
            )
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
            guard !parent.isVideoFullscreen else { return false }
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

/// Hosting model that remembers its page index so the pager's data
/// source can walk to neighbours.
private final class PhotoPageHost: UIHostingController<AnyView> {
    let index: Int
    let isVideo: Bool
    let loadState: DetailPageLoadState

    init(
        index: Int,
        isVideo: Bool,
        loadState: DetailPageLoadState,
        rootView: AnyView
    ) {
        self.index = index
        self.isVideo = isVideo
        self.loadState = loadState
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
