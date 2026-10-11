import AVKit
import CoreLocation
import ImageIO
import MapKit
import Photos
import ShotDexKit
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
    /// Drops photos a deletion through the sources removed (FS-19.04 §2).
    /// A requirement, not only an extension method, so a source's own
    /// version is the one a viewer calls.
    func removeDeleted(ids: Set<String>)
}

extension PhotoBrowsingSource {
    var sourceAlbum: PHAssetCollection? { nil }

    /// Sources that hold only Photos assets drop them on their next load.
    func removeDeleted(ids: Set<String>) {}

    /// Every photo the viewer is paging through, for Cull From Here
    /// (FS-01.12b §5). The default walks the indices — the whole list for a
    /// source that loads everything; a paging source (Albums) covers what
    /// it has loaded so far.
    func allPhotoIds() -> [String] {
        (0..<photoCount).compactMap(photoId(at:))
    }
}

/// Presentation target for the fullscreen viewer, captured at tap time. Holds
/// the stable id (for `fullScreenCover(item:)` identity) plus the starting
/// index — resolved once, so an in-viewer deletion that prunes the source can't
/// blank the cover by re-resolving a now-missing id every parent render.
struct PhotoViewerTarget: Identifiable, Equatable {
    let id: String
    let startIndex: Int
}

/// A pending slideshow — the run to play and where in it to start.
struct SlideshowPresentation: Identifiable {
    let id = UUID()
    let assetIds: [String]
    let startIndex: Int
}

private struct PhotoDetailActionTarget: Identifiable {
    let id: String
    let asset: PHAsset
    let sourceAlbum: PHAssetCollection?
    /// For the editor: the file *Edit which version?* chose.
    var editSource: PhotoEditSource? = nil
}

/// Fullscreen photo viewer: horizontal paging between photos, pinch/double-tap
/// zoom, swipe-down to dismiss, share, favorite, and the metadata panel.
struct PhotoDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppNavigation.self) private var navigation

    let model: any PhotoBrowsingSource
    @State var currentIndex: Int
    /// Opens the viewer in Compare — a selection or a Duplicates group
    /// (FS-01.08c §7).
    var compareRequest: CompareRequest? = nil
    /// Compare's stage covers the pager: the viewer's chrome and keys stand
    /// down so a key never means two things.
    @State private var isComparing = false
    /// Room the Single · 2-Up · Survey control takes in the top bar.
    @State private var modePickerWidth: CGFloat = 0

    /// Bumped after an in-viewer deletion prunes the source; forces the pager
    /// to rebuild the current page even when the (clamped) index is unchanged.
    @State private var reseatToken = 0
    @State private var isMetadataPresented = false
    /// Live Text: off by default so the analysis only runs when asked for, and
    /// so text selection never steals the pinch and swipe gestures.
    @State private var isLiveTextActive = false
    @State private var slideshow: SlideshowPresentation?
    /// Frames of the burst the current photo belongs to. Reuses the slideshow
    /// payload type: both are "a run of asset ids plus where to start".
    @State private var burstList: SlideshowPresentation?
    @State private var trimTarget: VideoTrimPresentation?
    @State private var panoramaTarget: PanoramaPresentation?
    /// The Handoff offer for the photo on screen, and the lookup that builds
    /// it — asking PhotoKit for a cloud identifier is a round trip.
    @State private var handoffActivity: NSUserActivity?
    @State private var handoffTask: Task<Void, Never>?
    @State private var isSavingLiveVideo = false
    @State private var liveVideoErrorMessage: String?
    /// Set while the Hide confirmation is up, holding the photo it is about.
    ///
    /// Hiding is one-way from inside this app: iOS 16 took the hidden album
    /// away from every app but Photos, so ShotDex can write the flag and then
    /// never see the photo again to undo it. That is exactly the case Apple's
    /// own guidance reserves an alert for.
    @State private var hideConfirmationAssetId: String?
    @State private var editorTarget: PhotoDetailActionTarget?
    /// Edit on a RAW this iOS build can't read says so instead of opening
    /// the editor (FS-03.04b §3).
    @State private var unsupportedRAWMessage: UnsupportedRAWMessage?
    @State private var isUnsupportedRAWCardPresented = false
    @Environment(UnsupportedRAWIndex.self) private var unsupportedRAWIndex: UnsupportedRAWIndex?
    /// Stars and flags (FS-01.12): read for line 2, written by ⋯ and the keys.
    @Environment(PhotoMarks.self) private var photoMarks: PhotoMarks?
    /// Cull From Here (FS-01.12b §5): the viewer's list, from this photo.
    @State private var cullRequest: CullRequest?
    /// Export… of the photo on screen (FS-03.07b §3).
    @State private var fileExportRequest: FileExportRequest?
    @State private var compressionTarget: PhotoDetailActionTarget?
    @State private var videoStudioTarget: PhotoDetailActionTarget?
    /// Asset saved by the editor, waiting for its cover to finish dismissing —
    /// then the viewer pages to it (Save Changes: this page rebuilt with the
    /// edit; Save Copy: the new copy, once the library change lands).
    @State private var pendingSavedAssetID: String?
    @State private var revealSavedTask: Task<Void, Never>?
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
    /// A photo with no asset — only in a folder, on a drive or on a server:
    /// whether its original can be opened now (FS-19.01b §1, FS-19.03 §6).
    @State private var fileReachability: CopyReachability?
    /// The ShotDex confirmation of a deletion that reaches a file or a
    /// server copy — those have no system dialog of their own (FS-19.04 §2).
    @State private var sourceDeletion: DeletionTargetQueries.Request?

    /// True for a photo that has no Photos asset: the Photos-only rows
    /// (Copy, Duplicate, Adjust Date and Location, Live Text) are not offered.
    private var isFilePhoto: Bool { currentAsset == nil && currentMetadata != nil }

    /// Share, Export and Delete need the original; an offline source dims them.
    private var filePhotoIsOffline: Bool { isFilePhoto && fileReachability?.canOpenOriginal == false }
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
    /// What the one offline check found for the page on screen (FS-02.06
    /// §4): only that page is asked, once per visit, and again when a
    /// download on it ends. Never stored — the system can offload an
    /// original again without saying so.
    @State private var originalAvailability: (id: String, value: OriginalAvailability)?
    @State private var originalProbeTask: Task<Void, Never>?

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
                originalFetcher: dependencies.originalFetcher,
                currentIndex: $currentIndex,
                reseatToken: reseatToken,
                videoBottomInset:
                    max(bottomChromeHeight, Self.estimatedActionBarHeight)
                    + safeAreaBottom
                    + Self.videoActionBarClearance,
                videoFullscreenEdgeInset: max(24, max(safeAreaTop, safeAreaBottom)),
                isVideoFullscreen: isVideoFullscreen,
                isVideoChromeVisible: isVideoChromeVisible,
                isLiveTextActive: isLiveTextActive,
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
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                infoPanel(metadata)
                                if filePhotoIsOffline, let note = fileReachability?.viewerNote {
                                    Text(note)
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.85))
                                        .padding(.horizontal, AppTheme.Spacing.md)
                                }
                            }
                        }
                    }
                    .padding(.trailing, modePickerWidth)
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
        // Zoomed in, the chrome is gone but the zoom is what downloads the
        // original: the ring alone, top-right, until it arrives (FS-02.06
        // AC-2). No number; VoiceOver reads the percent.
        .overlay(alignment: .topTrailing) { zoomedDownloadCorner }
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
        .compareHost(
            source: model,
            request: compareRequest,
            currentIndex: $currentIndex,
            reveal: { id in
                guard let index = model.index(of: id) else { return }
                currentIndex = index
                reseatToken += 1
                refreshCurrentPhoto()
            },
            isComparing: $isComparing,
            modePickerWidth: $modePickerWidth,
            showsChrome: showsViewerChrome
        )
        .preferredColorScheme(.dark)
        .statusBarHidden(shouldHideStatusBar)
        // The viewer is a fullScreenCover, so a sheet presented from the root
        // cannot reach over it — it hosts the shared action sheets itself.
        // Its own coordinator, not the root's: see `viewerAssetActions`.
        .assetActionHost(dependencies.viewerAssetActions)
        .appBannerHost(dependencies.banner, bottomInset: 120)
        .cullPresenter($cullRequest)
        .fileExportPresenter($fileExportRequest)
        .sheet(item: $burstList) { presentation in
            // Neither the root nor this viewer can present over this sheet,
            // so its tile menu gets a coordinator and host of its own.
            AssetActionScope(dependencies: dependencies) {
                NavigationStack {
                    PhotoListScreen(
                        title: String(localized: "Burst"),
                        subtitle: "\(presentation.assetIds.count) frames",
                        assetIds: presentation.assetIds
                    )
                }
            }
            .environment(dependencies)
            .environment(photoLibrary)
        }
        .fullScreenCover(item: $slideshow) { presentation in
            SlideshowScreen(
                assetIds: presentation.assetIds,
                startIndex: presentation.startIndex
            )
            .environment(photoLibrary)
        }
        .alert(
            "Couldn't Save Video",
            isPresented: Binding(
                get: { liveVideoErrorMessage != nil },
                set: { if !$0 { liveVideoErrorMessage = nil } }
            ),
            presenting: liveVideoErrorMessage
        ) { _ in
            Button("OK", role: .cancel) { liveVideoErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .sourceDeletion($sourceDeletion) { removed, _ in afterSourceDeletion(removed) }
        .onChange(of: currentIndex) { _, _ in
            isLiveTextActive = false
            recordCurrentAsViewed()
        }
        .onAppear {
            recordCurrentAsViewed()
            // The share sheet's "Edit in ShotDex" lands here and means the
            // editor, not the viewer. Consumed once, so paging to the next photo
            // is a plain view again.
            if navigation.consumePendingEditorRequest(), let currentAsset {
                openEditor(for: currentAsset)
            }
        }
        .sheet(isPresented: $isMetadataPresented) {
            MetadataPanel(
                asset: currentAsset,
                indexedMetadata: currentMetadata
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .unsupportedRAWAlert($unsupportedRAWMessage, shareOriginal: shareCurrentOriginal)
        .fullScreenCover(item: $editorTarget) { target in
            PhotoEditorScreen(
                asset: target.asset,
                sourceAlbum: target.sourceAlbum,
                // Only so a text overlay can say "Shot on …" — the row is already
                // in hand for the info panel.
                metadata: currentMetadata,
                editSource: target.editSource,
                onSaved: { pendingSavedAssetID = $0 }
            )
        }
        // Reveal only once the cover is gone — paging the viewer underneath a
        // dismissing full-screen cover just flashes.
        .onChange(of: editorTarget?.id) { _, targetID in
            if targetID == nil { revealSavedAssetIfNeeded() }
        }
        .fullScreenCover(item: $compressionTarget) { target in
            CompressionScreen(
                assets: [target.asset],
                sourceAlbum: target.sourceAlbum
            )
        }
        .fullScreenCover(item: $videoStudioTarget) { target in
            VideoStudioScreen(
                assets: [target.asset],
                mode: .singleVideo,
                onSaved: { pendingSavedAssetID = $0 }
            )
        }
        .onChange(of: videoStudioTarget?.id) { _, targetID in
            if targetID == nil { revealSavedAssetIfNeeded() }
        }
        .fullScreenCover(item: $panoramaTarget) { target in
            PanoramaScreen(asset: target.asset)
        }
        .fullScreenCover(item: $trimTarget) { target in
            VideoTrimScreen(asset: target.asset) {
                // The clip's own bytes changed, so the page has to be rebuilt:
                // its `AVPlayerItem` still points at the untrimmed version.
                reseatToken += 1
                refreshCurrentPhoto()
            }
        }
        .viewerAlerts(
            hideAssetId: $hideConfirmationAssetId,
            onHide: { dependencies.viewerAssetActions.toggleHidden(ids: [$0]) }
        )
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
            revealSavedTask?.cancel()
            revealSavedTask = nil
            // Closing the viewer withdraws the offer: nothing is on screen to
            // hand over any more.
            handoffTask?.cancel()
            handoffTask = nil
            handoffActivity?.invalidate()
            handoffActivity = nil
        }
    }

    /// Pages the viewer to the asset the editor just saved. Save Changes finds
    /// its index on the first try (same asset) — the reseat still matters, it
    /// rebuilds the page so the edited render replaces the cached one. Save
    /// Copy has to wait for the library change and the index's fast pass to put
    /// the new asset into the source, so this polls briefly instead of giving
    /// up on the first miss.
    private func revealSavedAssetIfNeeded() {
        guard let assetID = pendingSavedAssetID else { return }
        pendingSavedAssetID = nil
        revealSavedTask?.cancel()
        revealSavedTask = Task {
            for _ in 0..<20 {
                guard !Task.isCancelled else { return }
                if let index = model.index(of: assetID) {
                    currentIndex = index
                    reseatToken += 1
                    refreshCurrentPhoto()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
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
        fileReachability = currentAsset == nil
            ? try? CopyReachabilityQueries(database: dependencies.database).reachability(photoId: assetId)
            : nil
        updateFilename(assetId: assetId)
        probeOriginal()
        publishHandoffActivity()
    }

    /// Offers the photo on screen to the user's other devices.
    ///
    /// Re-published on every page change and cancelled when the viewer closes,
    /// so the Handoff banner always names the photo actually in front of the
    /// user. A photo with no cloud identity publishes nothing and clears what
    /// was there — handing over a photo the other device cannot find is worse
    /// than offering nothing.
    private func publishHandoffActivity() {
        handoffTask?.cancel()
        guard let asset = currentAsset else {
            handoffActivity?.invalidate()
            handoffActivity = nil
            return
        }
        let title = currentFilename
        handoffTask = Task {
            let activity = await HandoffActivity.activity(for: asset, title: title)
            guard !Task.isCancelled else { return }
            handoffActivity?.invalidate()
            handoffActivity = activity
            activity?.becomeCurrent()
        }
    }

    /// Asks, with the network off, whether the page's original is on the
    /// device (FS-02.06 AC-1). Reads a header, never downloads: the screen
    /// sized image is the pages' own business, the original comes only on
    /// zoom.
    private func probeOriginal() {
        originalProbeTask?.cancel()
        guard let asset = currentAsset, asset.mediaType == .image else {
            originalAvailability = nil
            return
        }
        let id = asset.localIdentifier
        if originalAvailability?.id != id { originalAvailability = nil }
        let item = OriginalItem(
            id: id,
            filename: currentFilename ?? "",
            photo: PixelSize(width: asset.pixelWidth, height: asset.pixelHeight)
        )
        let fetcher = dependencies.originalFetcher
        originalProbeTask = Task { @MainActor in
            let value = await fetcher.probe(item)
            guard !Task.isCancelled, currentAsset?.localIdentifier == id else { return }
            withAnimation(.easeInOut(duration: 0.2)) { originalAvailability = (id, value) }
        }
    }

    /// Whether the page on screen has its original only in iCloud.
    private var isOriginalInCloud: Bool {
        guard let originalAvailability, originalAvailability.id == currentAsset?.localIdentifier else { return false }
        return originalAvailability.value == .inCloud
    }

    /// Stores a page's download report and, when it is the visible page,
    /// reflects it in the ring. Keeps only a small window around the current
    /// index so the map can't grow across a large library.
    private func recordDownloadState(index: Int, progress: Double, downloading: Bool) {
        let wasDownloading = pageDownload[index]?.downloading == true
        pageDownload[index] = (progress, downloading)
        // A download on the page on screen just ended: ask again, so the
        // glyph goes once the original is here (AC-2).
        if index == currentIndex, wasDownloading, !downloading { probeOriginal() }
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

    private var zoomedDownloadIndicator: ViewerDownloadIndicator {
        .placement(
            isChromeVisible: showsViewerChrome,
            isZoomed: isZoomed,
            isDownloading: isDownloading,
            isStalled: isDownloadStalled
        )
    }

    /// The top-right corner of the photo area, inside the safe area and the
    /// chrome's 20 pt margin, so the display's rounded corner never cuts it.
    @ViewBuilder private var zoomedDownloadCorner: some View {
        Group {
            switch zoomedDownloadIndicator {
            case .cornerRing:
                ICloudDownloadRing(progress: downloadProgress)
            case .cornerStall:
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel(String(localized: "iCloud download stalled"))
            default:
                EmptyView()
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 20)
        .allowsHitTesting(false)
    }

    private var showsViewerChrome: Bool {
        !isComparing
            && !isZoomed
            && !isVideoFullscreen
            && (!isCurrentVideo || isVideoChromeVisible)
    }

    private var shouldHideStatusBar: Bool {
        isVideoFullscreen || (isCurrentVideo && !isVideoChromeVisible)
    }

    /// Photos-style three-zone action row: Share is isolated at the leading
    /// edge, Delete at the trailing edge, and non-destructive actions share one
    /// centered glass capsule.
    ///
    /// One `HStack`, not a centred overlay: the capsule grows with the number of
    /// actions the photo offers, and layered over the row it simply ran on top
    /// of Share and Delete — seven controls want 288pt of a 234pt gap on a
    /// 402pt phone. Laid out in line it cannot overlap, and the capsule still
    /// lands dead centre because the two round buttons are the same width.
    private func actionBar(_ metadata: PhotoMetadata) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            GlassIconButton(
                systemImage: "square.and.arrow.up",
                accessibilityLabel: "Share"
            ) {
                showVideoChrome()
                share(metadata)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(filePhotoIsOffline)
            .opacity(filePhotoIsOffline ? 0.4 : 1)

            Spacer(minLength: AppTheme.Spacing.sm)

            GlassPanel(cornerRadius: AppTheme.Radius.xl) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    actionBarCenterButton(
                        systemImage: metadata.isFavorite ? "heart.fill" : "heart",
                        accessibilityLabel: metadata.isFavorite ? "Unfavorite" : "Favorite"
                    ) {
                        showVideoChrome()
                        toggleFavorite(metadata)
                    }
                    // Hardware-keyboard shortcuts, for iPad and a Mac running
                    // the app. They hang off the buttons so the shortcut and the
                    // tap always run the same code.
                    .keyboardShortcut("f", modifiers: [])
                    actionBarCenterButton(
                        systemImage: "info.circle",
                        accessibilityLabel: "Info"
                    ) {
                        showVideoChrome()
                        isMetadataPresented = true
                    }
                    .keyboardShortcut("i", modifiers: [])
                    if !isCurrentVideo, let currentAsset {
                        actionBarCenterButton(
                            systemImage: "slider.horizontal.3",
                            accessibilityLabel: "Edit"
                        ) {
                            openEditor(for: currentAsset)
                        }
                    }
                    if isCurrentVideo, let currentAsset {
                        actionBarCenterButton(
                            systemImage: "slider.horizontal.3",
                            accessibilityLabel: "Edit"
                        ) {
                            showVideoChrome()
                            videoStudioTarget = PhotoDetailActionTarget(
                                id: currentAsset.localIdentifier,
                                asset: currentAsset,
                                sourceAlbum: model.sourceAlbum
                            )
                        }
                    }
                    overflowMenu(metadata)
                }
                .padding(.horizontal, AppTheme.Spacing.xs)
                .frame(height: AppTheme.Size.darkActionIcon + 2 * AppTheme.Spacing.xs)
            }

            Spacer(minLength: AppTheme.Spacing.sm)

            GlassIconButton(systemImage: "trash", accessibilityLabel: "Delete") {
                showVideoChrome()
                deleteCurrentPhoto()
            }
            .keyboardShortcut(.delete, modifiers: [])
            // A file photo on a source that is away cannot be moved to its
            // Trash now.
            .disabled(filePhotoIsOffline)
            .opacity(filePhotoIsOffline ? 0.4 : 1)
        }
        .background { PhotoMarkKeyButtons(ids: { currentMetadata.map { [$0.assetId] } ?? [] }) }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppTheme.Size.floatingChromeMargin)
        .padding(.bottom, AppTheme.Spacing.md)
    }

    /// Everything that does not earn a button of its own, in the order Photos
    /// keeps it: organise first, then the corrections, then the destructive row.
    /// Same action set as the grid's tile menu, plus the two that only make
    /// sense with a photo open — jumping to it on the map, and lifting its text.
    @ViewBuilder
    private func overflowMenu(_ metadata: PhotoMetadata) -> some View {
        let actions = dependencies.viewerAssetActions
        let id = metadata.assetId
        Menu {
            // Marks first: the viewer's chrome stays as it is, so the menu
            // is where they are set by touch (FS-01.12 §7).
            Section {
                PhotoMarkMenus(ids: [id])
                Button {
                    cullRequest = CullRequest(assetIds: model.allPhotoIds(), startId: id)
                } label: {
                    Label(MarkCopy.cullFromHere, systemImage: PhotoCommand.cull.systemImage)
                }
            }
            Section {
                Button {
                    actions.presentAddToCollection(ids: [id])
                } label: {
                    Label("Add to Collection", systemImage: "rectangle.stack.badge.plus")
                }
                if !isFilePhoto {
                    Button {
                        actions.duplicate(ids: [id])
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                }
                if !isCurrentVideo, !isFilePhoto {
                    Button {
                        actions.copyToPasteboard(id: id)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button {
                        isLiveTextActive.toggle()
                    } label: {
                        Label(
                            isLiveTextActive
                                ? "Stop Selecting in Photo"
                                : "Select Text or Subject",
                            systemImage: "text.viewfinder"
                        )
                    }
                    if currentAsset?.mediaSubtypes.contains(.photoLive) == true {
                        Button {
                            saveLivePhotoAsVideo()
                        } label: {
                            Label("Save as Video", systemImage: "film")
                        }
                        .disabled(isSavingLiveVideo)
                    }
                }
            }

            Section {
                if isCurrentVideo, let currentAsset {
                    Button {
                        trimTarget = VideoTrimPresentation(asset: currentAsset)
                    } label: {
                        Label("Trim", systemImage: "scissors")
                    }
                }
                if !isCurrentVideo, let currentAsset {
                    // "Resize", not "Compress": the Library's selection menu
                    // and the tile menu both call it that, and the same action
                    // must read the same everywhere.
                    Button {
                        compressionTarget = PhotoDetailActionTarget(
                            id: currentAsset.localIdentifier,
                            asset: currentAsset,
                            sourceAlbum: model.sourceAlbum
                        )
                    } label: {
                        Label("Resize", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                }
                // Right under Resize, for photos and videos alike
                // (FS-03.07c §1 item 1).
                if !isFilePhoto {
                    Button {
                        fileExportRequest = FileExportRequest(model: .make(assetIds: [id], dependencies: dependencies))
                    } label: {
                        PhotoCommand.export.label
                    }
                    Button {
                        actions.presentAdjustDate(ids: [id])
                    } label: {
                        Label("Adjust Date & Time", systemImage: "calendar")
                    }
                    Button {
                        actions.presentAdjustLocation(ids: [id])
                    } label: {
                        Label("Adjust Location", systemImage: "mappin.and.ellipse")
                    }
                }
                if metadata.latitude != nil, metadata.longitude != nil {
                    Button {
                        openInMaps(metadata)
                    } label: {
                        Label("Show on Map", systemImage: "map")
                    }
                }
            }

            Section {
                // Only where it means something. Opened from the Library the
                // photo is already in All Photos, so the row would do nothing;
                // from an album, a trip, a memory or a search result it is the
                // way back to where the photo sits among everything else.
                if !(model is LibraryModel), let id = currentAsset?.localIdentifier {
                    Button {
                        dismiss()
                        navigation.openPhoto(assetId: id)
                    } label: {
                        Label("Show in All Photos", systemImage: "photo.on.rectangle.angled")
                    }
                }
                if let currentAsset,
                   PanoramaRecognition.isPanorama(asset: currentAsset, metadata: currentMetadata) {
                    Button {
                        panoramaTarget = PanoramaPresentation(asset: currentAsset)
                    } label: {
                        Label("View Panorama", systemImage: "pano")
                    }
                }
                if currentAsset?.burstIdentifier != nil {
                    Button {
                        showBurst()
                    } label: {
                        Label("Show All Frames", systemImage: "square.stack.3d.down.right")
                    }
                }
                Button {
                    startSlideshow()
                } label: {
                    Label("Slideshow", systemImage: "play.rectangle")
                }
                .disabled(model.photoCount < 2)
            }

            Section {
                Button(role: .destructive) {
                    hideConfirmationAssetId = id
                } label: {
                    Label("Hide", systemImage: "eye.slash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More actions")
    }

    /// Notes the photo on screen as recently viewed. Called on appear and on
    /// every page change, so paging through a hundred photos records all of
    /// them in the order they were seen.
    private func recordCurrentAsViewed() {
        guard let id = model.photoId(at: currentIndex) else { return }
        dependencies.recentActivity.recordViewed(id)
    }

    /// Opens every frame of the burst this photo belongs to. The grid only
    /// ever shows the representative, so without this the other frames are
    /// invisible in the app.
    private func showBurst() {
        guard let asset = currentAsset else { return }
        let members = PhotoLibraryService.burstMembers(of: asset)
        guard members.count > 1 else { return }
        burstList = SlideshowPresentation(
            assetIds: members.map(\.localIdentifier),
            startIndex: 0
        )
    }

    /// Plays the whole run the viewer is browsing, starting from the photo on
    /// screen. Videos are skipped — a slideshow that stops to play a clip is a
    /// different feature, and Video Studio already covers it.
    private func startSlideshow() {
        var ids: [String] = []
        ids.reserveCapacity(model.photoCount)
        for offset in 0..<model.photoCount {
            guard let id = model.photoId(at: offset) else { continue }
            guard model.asset(for: id)?.mediaType != .video else { continue }
            ids.append(id)
        }
        guard ids.count > 1 else { return }
        let currentId = model.photoId(at: currentIndex)
        slideshow = SlideshowPresentation(
            assetIds: ids,
            startIndex: currentId.flatMap { ids.firstIndex(of: $0) } ?? 0
        )
    }

    /// Copies the motion half of a Live Photo out as a standalone clip, the
    /// way Photos' "Save as Video" does. The still is left untouched.
    private func saveLivePhotoAsVideo() {
        guard let asset = currentAsset, !isSavingLiveVideo else { return }
        isSavingLiveVideo = true
        Task {
            defer { isSavingLiveVideo = false }
            guard let url = await LivePhotoLoader.exportVideo(asset: asset) else {
                liveVideoErrorMessage = String(
                    localized: "This Live Photo has no motion to save."
                )
                return
            }
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                _ = try await photoLibrary.importFile(at: url, isVideo: true)
                photoLibrary.publishAppCreatedAsset()
            } catch {
                liveVideoErrorMessage = error.localizedDescription
            }
        }
    }

    /// Hands the photo's coordinate to Maps, which is the one place the app
    /// cannot show: driving directions and the surrounding area.
    private func openInMaps(_ metadata: PhotoMetadata) {
        guard let latitude = metadata.latitude, let longitude = metadata.longitude else { return }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
        item.name = currentFilename ?? String(localized: "Photo Location")
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
        ])
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
                // 40pt is the dark action-bar icon size (DESIGN.md §6). The
                // minimum lets the row give way on a narrow phone rather than
                // pushing the capsule into Share and Delete.
                .frame(
                    minWidth: 32,
                    maxWidth: AppTheme.Size.darkActionIcon,
                    minHeight: AppTheme.Size.darkActionIcon
                )
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
        let raw = currentAsset.flatMap { unsupportedRAWIndex?.message(for: $0.localIdentifier) }
        // The RAW glyph is a button of its own beside the panel's, so its
        // 44pt target and its card don't open the Info sheet (FS-03.04b AC-17).
        return ZStack(alignment: .topTrailing) {
            infoPanelButton(metadata, reservesRAWGlyph: raw != nil)
            if let raw {
                unsupportedRAWGlyph(raw)
                    // Centred on the slot the title row keeps for it: 12pt
                    // panel inset, then the iCloud glyph when there is one.
                    .padding(.trailing, (hasCloudGlyph ? 12 + 22 + 8 : 12) - 14)
                    .offset(y: -5)
            }
        }
    }

    private var hasCloudGlyph: Bool { isDownloadStalled || isDownloading || isOriginalInCloud }

    /// The warning glyph and its card: the camera, the iOS version, and that
    /// the preview stays viewable while the RAW can't be edited.
    private func unsupportedRAWGlyph(_ raw: UnsupportedRAWMessage) -> some View {
        Button {
            isUnsupportedRAWCardPresented = true
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "RAW not supported by iOS"))
        .accessibilityHint(String(localized: "Shows why this RAW can't be edited", comment: "VoiceOver hint: the viewer's unsupported-RAW glyph"))
        .popover(isPresented: $isUnsupportedRAWCardPresented) {
            Text(raw.viewerCard)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(width: 300, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func infoPanelButton(_ metadata: PhotoMetadata, reservesRAWGlyph: Bool) -> some View {
        let summary = panelSummary(metadata)
        // A Button, not `onTapGesture`: the panel is the second way into the
        // Photo Info sheet and has to be reachable by VoiceOver/Switch Control.
        return Button {
            isMetadataPresented = true
        } label: {
            GlassPanel(cornerRadius: AppTheme.Radius.lg) {
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
                                .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        }
                        Spacer()
                        if reservesRAWGlyph {
                            // The RAW glyph's slot; the glyph itself is the
                            // button laid over it (`unsupportedRAWGlyph`).
                            Color.clear.frame(width: 16, height: 14)
                        }
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
                        } else if isOriginalInCloud {
                            // The original is in iCloud; what is on screen is
                            // the device's copy (FS-02.06 AC-1).
                            Image(systemName: "icloud")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                                // The panel's own label is not always the one
                                // read: the children are, so the glyph names
                                // itself rather than "Icloud".
                                .accessibilityLabel(String(localized: "Original in iCloud"))
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
            marks: currentMarks(metadata),
            measureDetail: { Self.width(of: $0, style: .caption2) }
        )
    }

    // MARK: Stars and flags (FS-01.12)

    /// The current photo's marks. Reads `version` so a change from a key, the
    /// menu or another surface redraws line 2.
    private func currentMarks(_ metadata: PhotoMetadata) -> PhotoMarkSummary? {
        guard let photoMarks else { return nil }
        _ = photoMarks.version
        return photoMarks.summary(for: metadata.assetId, photosRating: currentAsset?.photosStarRating)
    }

    /// Announces every field even when the visible lines dropped some, plus
    /// whatever the trailing badge and glyph are saying visually.
    private func accessibilityPanelLabel(_ summary: PhotoInfoPanelSummary) -> String {
        var parts = [summary.accessibilityText]
        if let badge = formatBadge { parts.append(badge) }
        if isDownloadStalled {
            parts.append(String(localized: "iCloud download stalled"))
        } else if isDownloading {
            // The ring has no number; VoiceOver reads one (FS-02.06 §8).
            parts.append(OriginalPreparationState.accessibilityProgress(downloadProgress))
        } else if isOriginalInCloud {
            parts.append(String(localized: "Original in iCloud", comment: "VoiceOver: the photo's original is only in iCloud"))
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

    /// Edit: the editor, unless the photo is a RAW the index already knows
    /// this iOS build can't read — then the message, at once, with nothing
    /// loaded or downloaded (FS-03.04b AC-3, AC-4).
    private func openEditor(for asset: PHAsset) {
        if let message = unsupportedRAWIndex?.message(for: asset.localIdentifier) {
            unsupportedRAWMessage = message
            return
        }
        let album = model.sourceAlbum
        let choice = EditSourceChoice(
            resources: EditSourcePrompt.resources(of: asset),
            rawIsReadable: !(unsupportedRAWIndex?.isCameraUnreadable(assetId: asset.localIdentifier) ?? false)
        )
        guard choice.isPair else {
            editorTarget = PhotoDetailActionTarget(id: asset.localIdentifier, asset: asset, sourceAlbum: album)
            return
        }
        // Every pair asks, every time (AC-5, AC-16).
        Task { @MainActor in
            guard let source = await EditSourcePrompt.ask(choice) else { return }
            editorTarget = PhotoDetailActionTarget(
                id: asset.localIdentifier, asset: asset, sourceAlbum: album, editSource: source
            )
        }
    }

    /// Share Original from the unreadable-DNG alert (FS-03.04b AC-7): the
    /// viewer's own share, which hands an untouched RAW over byte for byte
    /// and asks the RAW question below All Metadata (AC-8).
    private func shareCurrentOriginal() {
        guard let asset = currentAsset else { return }
        let downloads = dependencies.originalDownloads
        // The alert is the decoder's word for this file, index or not.
        let unreadable: Set<String> = [asset.localIdentifier]
        Task { await PhotoShareSheet.share(assets: [asset], downloads: downloads, unreadableRAW: unreadable) }
    }

    /// The tile's badge, from the same extension table (FS-03.04b §2).
    private var formatBadge: String? {
        guard let filename = currentFilename else { return nil }
        return FileTypeBadge.text(forExtension: (filename as NSString).pathExtension)
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
    /// After the ShotDex confirmation ran: the source drops what went, and
    /// the viewer moves on the way a Photos deletion does.
    private func afterSourceDeletion(_ removed: Set<String>) {
        guard !removed.isEmpty else { return }
        model.removeDeleted(ids: removed)
        let count = model.photoCount
        guard count > 0 else {
            dismiss()
            return
        }
        currentIndex = min(currentIndex, count - 1)
        reseatToken += 1
        refreshCurrentPhoto()
    }

    private func deleteCurrentPhoto() {
        guard let assetId = model.photoId(at: currentIndex) else { return }
        let roots = dependencies.folderRoots
        if let request = try? DeletionTargetQueries(database: dependencies.database, hasTrash: { roots.hasTrash($0) })
            .request(photoIds: [assetId], selection: .photos) {
            sourceDeletion = request
            return
        }
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

    /// The same lazy share as the grid (FS-02.06 §9, FS-08.06 AC-5): the
    /// share sheet opens at once, and a photo only in iCloud downloads in the
    /// Share modal once a destination asks. A video goes as it is.
    private func share(_ metadata: PhotoMetadata) {
        guard let asset = model.asset(for: metadata.assetId) else {
            // A folder photo shares its file as it is.
            if let url = photoLibrary.filePhotoURL(metadata.assetId) { PhotoShareSheet.present(items: [url]) }
            return
        }
        let downloads = dependencies.originalDownloads
        let unreadable = unsupportedRAWIndex?.assetIds ?? []
        Task { await PhotoShareSheet.share(assets: [asset], downloads: downloads, unreadableRAW: unreadable) }
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
    @AppStorage(SettingsKeys.autoplayVideos) private var autoplayVideos = true

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
            // Autoplay is a preference, the way it is in Photos. Pausing on
            // leaving is not — a page that scrolled away must always stop.
            if isActive, autoplayVideos {
                model.play()
            }
            syncBufferingIndicator(for: model.phase)
        }
        .onChange(of: isActive) { _, active in
            if active {
                if autoplayVideos { model.play() }
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
        VStack(spacing: 18) {
            centerTransportRow
            frameStepRow
                .opacity(model.isPlaying ? 0 : 1)
                // A hidden row must not take the taps meant for the picture.
                .allowsHitTesting(!model.isPlaying)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.18),
                    value: model.isPlaying
                )
        }
    }

    private var centerTransportRow: some View {
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
        .background {
            Button("Step back one frame") {
                onInteraction()
                model.stepFrame(by: -1)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .opacity(0)

            Button("Step forward one frame") {
                onInteraction()
                model.stepFrame(by: 1)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .opacity(0)
        }
    }

    /// Frame stepping, on screen only while the clip is paused.
    ///
    /// It used to be arrow keys alone, on the grounds that the centre row was
    /// already three targets wide and the panel below it six. Keeping it to a
    /// paused clip resolves that: stepping is what someone does when they have
    /// stopped to look at one frame, `stepFrame` pauses anyway, and while the
    /// clip is playing these two targets are not on screen to crowd anything.
    ///
    /// Smaller and lower-contrast than the transport above: this is inspection,
    /// not navigation, and it must not compete with play.
    private var frameStepRow: some View {
        HStack(spacing: 16) {
            frameStepButton(systemImage: "backward.frame.fill", label: "Step back one frame", frames: -1)
            Text("Frame")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            frameStepButton(systemImage: "forward.frame.fill", label: "Step forward one frame", frames: 1)
        }
    }

    private func frameStepButton(
        systemImage: String,
        label: String,
        frames: Int
    ) -> some View {
        Button {
            onInteraction()
            model.stepFrame(by: frames)
        } label: {
            ZStack {
                Circle().fill(.black.opacity(0.28))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
            VStack(spacing: 8) {
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
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
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
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
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
    /// Live Text on this page. Off unless the viewer's ⋯ menu turns it on, and
    /// reset whenever the viewer pages to another photo.
    var isLiveTextActive = false
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
    var originalFetcher: (any OriginalFetching)?
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
    @AppStorage(SettingsKeys.viewFullHDR) private var showsFullHDR = false
    @State private var isVideo = false
    @State private var asset: PHAsset?
    /// Whether this page's asset carries a motion track.
    @State private var isLivePhoto = false
    /// Non-nil only for the length of one playback, then cleared by the
    /// player's end-of-playback callback.
    @State private var livePhoto: PHLivePhoto?
    @State private var isLoadingLivePhoto = false
    /// Whether this photo has been edited, so holding it is worth offering.
    @State private var hasEdits = false
    /// The unedited frame, fetched the first time the user holds the photo and
    /// kept for the rest of the page's life — comparing is something people do
    /// repeatedly, and re-fetching on every press would stutter.
    @State private var originalImage: UIImage?
    @State private var isShowingOriginal = false
    @State private var originalRequestId: PHImageRequestID?
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
                    image: isShowingOriginal ? (originalImage ?? image) : image,
                    onZoomStart: loadFullResolution,
                    onZoomChange: handleZoom,
                    isLiveTextActive: loadState.isLiveTextActive,
                    showsFullHDR: showsFullHDR,
                    onHoldChange: hasEdits ? { holding in
                        if holding { showOriginal() } else { hideOriginal() }
                    } : nil
                )
                .overlay {
                    if let livePhoto {
                        LivePhotoPlayerView(livePhoto: livePhoto) {
                            self.livePhoto = nil
                        }
                        .allowsHitTesting(false)
                    }
                }
                // Press and hold to see the photo as it was shot — the
                // comparison the editor has, in the place people actually
                // notice an edit. Offered only on an edited photo; the
                // recognizer itself lives in `ZoomableImageView`.
                // Bottom-centre, not the top: the viewer's own close button
                // and title capsule own the top of the page, and this page
                // draws edge to edge, so a badge up there lands behind them.
                .overlay(alignment: .bottom) {
                    if isShowingOriginal {
                        Text("Original")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.bottom, loadState.videoBottomInset + 12)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                // Bottom-left rather than Photos' top-left: this viewer already
                // owns the top-left with its close button and title capsule, and
                // the page draws edge to edge so it cannot inset itself below
                // them reliably. The bottom-left corner is free at every size.
                .overlay(alignment: .bottomLeading) {
                    if isLivePhoto, loadState.isActive {
                        LivePhotoBadge(isPlaying: livePhoto != nil) {
                            playLivePhoto()
                        }
                        .padding(.leading, 16)
                        .padding(.bottom, loadState.videoBottomInset + 12)
                        .opacity(isLoadingLivePhoto ? 0.5 : 1)
                        .disabled(isLoadingLivePhoto || livePhoto != nil)
                    }
                }
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

    /// Fetches the motion track on demand and plays it once. Photos only
    /// starts a Live Photo on a deliberate gesture too — loading every one on
    /// sight would pull a video for each page the pager preloads.
    private func showOriginal() {
        guard let asset else { return }
        withAnimation(.easeInOut(duration: 0.15)) { isShowingOriginal = true }
        guard originalImage == nil, originalRequestId == nil else { return }
        originalRequestId = photoLibrary.requestOriginalImage(
            for: asset,
            targetSize: targetSize
        ) { image in
            originalRequestId = nil
            guard let image else { return }
            originalImage = image
        }
    }

    private func hideOriginal() {
        guard isShowingOriginal else { return }
        withAnimation(.easeInOut(duration: 0.15)) { isShowingOriginal = false }
    }

    private func playLivePhoto() {
        guard let asset, livePhoto == nil, !isLoadingLivePhoto else { return }
        isLoadingLivePhoto = true
        Task {
            defer { isLoadingLivePhoto = false }
            let loaded = await LivePhotoLoader.load(
                asset: asset,
                targetSize: ActiveDisplay.pixelSize()
            )
            guard let loaded, self.asset?.localIdentifier == asset.localIdentifier else { return }
            livePhoto = loaded
        }
    }

    private func load() {
        guard let assetId = source.photoId(at: index) else { return }
        guard let asset = source.asset(for: assetId) else {
            loadFilePhoto(assetId)
            return
        }
        self.asset = asset
        isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
        // Off the main actor: resource enumeration can reach for on-demand
        // metadata, and this runs for every page the pager builds.
        if asset.mediaType == .image {
            Task.detached(priority: .utility) {
                let edited = PhotoLibraryService.hasEdits(asset)
                await MainActor.run { hasEdits = edited }
            }
        }
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

    private var targetSize: CGSize { ActiveDisplay.pixelSize() }

    /// A photo only in a folder or on a drive (FS-19.02 §3): its file, read
    /// at screen size by ImageIO — the embedded preview of a RAW when that is
    /// big enough, never a full decode — with the cached tile first.
    private func loadFilePhoto(_ id: String) {
        if image == nil, let tile = photoLibrary.fileThumbnails.image(for: id) {
            image = tile
            imageQuality = .thumbnail
        }
        let resolve = photoLibrary.filePhotoURL
        let longSide = Int(max(targetSize.width, targetSize.height))
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let url = resolve(id),
                      let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: longSide,
                      ] as CFDictionary)
                else { return nil }
                return UIImage(cgImage: cgImage)
            }.value
            guard let loaded, source.photoId(at: index) == id else { return }
            image = loaded
            imageQuality = .displayFinal
        }
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
        guard let originalFetcher else { return requestFullResolution(asset) }
        // PhotoKit's fetcher returns at once and the request below reports
        // its own progress; a scripted one plays its download first, so the
        // simulator can show the ring filling (FS-02.06 AC-2).
        let id = asset.localIdentifier
        let index = index
        let report = onDownloadStateChange
        Task { @MainActor in
            try? await originalFetcher.scriptedTransfer(for: id) { value in
                Task { @MainActor in
                    guard loadState.isActive else { return }
                    report?(index, value, true)
                }
            }
            requestFullResolution(asset)
        }
    }

    private func requestFullResolution(_ asset: PHAsset) {
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
    /// Plays a scripted download before the zoom's own request (FS-02.06);
    /// PhotoKit's returns at once.
    let originalFetcher: any OriginalFetching
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
    /// Live Text for the page currently on screen.
    let isLiveTextActive: Bool
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
        context.coordinator.applyLiveTextState(pager)
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
                originalFetcher: parent.originalFetcher,
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
        /// Live Text belongs to the page on screen only — a neighbour page
        /// that is merely preloaded must not start an analysis.
        func applyLiveTextState(_ pager: UIPageViewController) {
            guard let host = pager.viewControllers?.first as? PhotoPageHost else { return }
            host.loadState.isLiveTextActive = parent.isLiveTextActive
        }

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
            let targetSize = ActiveDisplay.pixelSize()
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

/// The viewer's alert, lifted out of its body: one more `.alert` inline
/// and the type-checker gives up on a view this size.
private extension View {
    func viewerAlerts(
        hideAssetId: Binding<String?>,
        onHide: @escaping (String) -> Void
    ) -> some View {
        self
            // Hiding is one-way from inside this app: iOS 16 took the hidden
            // album away from every app but Photos, so ShotDex can set the
            // flag and then never see the photo again to undo it — the case
            // Apple reserves an alert for.
            .alert(
                "Hide this photo?",
                isPresented: Binding(
                    get: { hideAssetId.wrappedValue != nil },
                    set: { if !$0 { hideAssetId.wrappedValue = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { hideAssetId.wrappedValue = nil }
                Button("Hide", role: .destructive) {
                    if let id = hideAssetId.wrappedValue { onHide(id) }
                    hideAssetId.wrappedValue = nil
                }
            } message: {
                Text("It moves to the Hidden album in Photos. ShotDex can't show hidden photos, so you'll need the Photos app to unhide it.")
            }
    }
}
