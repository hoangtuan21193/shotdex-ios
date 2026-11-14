import AVFoundation
import Foundation
import ImageIO
import Photos
import PhotosUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import os

/// The app's view of photo library authorization.
enum PhotoAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .authorized
        case .limited: self = .limited
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }

    var canReadLibrary: Bool { self == .authorized || self == .limited }
}

/// Errors surfaced while importing external files into the photo library.
enum PhotoImportError: Error {
    /// PhotoKit reported success but produced no asset placeholder.
    case creationFailed
}

/// Failures reading a video asset for playback.
enum PhotoVideoError: LocalizedError {
    /// PhotoKit returned neither a player item nor an error — the clip has no
    /// playable version available (typically an iCloud item it will not serve).
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This video isn’t available on this device."
        }
    }
}

/// Wraps PhotoKit: authorization, asset fetching, thumbnails, favorites,
/// and library change observation. Nothing above this layer touches Photos.
@MainActor
@Observable
final class PhotoLibraryService: NSObject {
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "photoauth")

    private(set) var authorizationState: PhotoAuthorizationState
    /// Bumped on every library change — including content-only ones (a rendition
    /// downloaded, a favorite toggled). For consumers whose data can change
    /// without the asset list changing: album lists and their counts.
    private(set) var libraryChangeToken = 0
    /// Bumped only when the browsable asset list itself changed: insertions,
    /// removals, or moves. The Library grid and the index pipeline observe this
    /// one, so viewing a photo (which makes PhotoKit cache renditions) never
    /// triggers a full-library reload or a fresh index pass.
    private(set) var assetChangeToken = 0
    /// Bumped only when the set of **albums** changed: one created, deleted,
    /// renamed, or its membership edited.
    ///
    /// Neither of the other two answers this. `assetChangeToken` is about the
    /// browsable asset list, and creating an empty album moves no asset, so
    /// the Collections tab did not reload and a just-created album was
    /// invisible until the next launch. `libraryChangeToken` does fire, but
    /// it fires on content-only changes too — about once a second while
    /// iCloud streams during an index run — which is why the tab stopped
    /// observing it in the first place.
    private(set) var collectionChangeToken = 0

    /// The pair the Collections tab reloads on. One value so it can be a
    /// `.task(id:)`, and a named type so the reason there are two is written
    /// down where the tab reads it.
    var collectionsTabTokens: LibraryChangeTokens {
        LibraryChangeTokens(asset: assetChangeToken, collection: collectionChangeToken)
    }

    /// Thumbnails of photos that live only in folders, on drives or on a
    /// server (FS-19.01b §5): a grid cell with no asset paints from here.
    @ObservationIgnored
    let fileThumbnails = FileThumbnailIndex()
    /// The file a photo with no asset opens from — its first reachable copy
    /// in a folder or on a drive (FS-19.02 §3); nil when none is reachable.
    @ObservationIgnored
    var filePhotoURL: @Sendable (String) -> URL? = { _ in nil }

    /// The file a photo or video was kept as on this device (Keep on This
    /// iPhone); nil when it is not kept or not here yet.
    @ObservationIgnored
    var keptFileURL: @Sendable (String) -> URL? = { _ in nil }

    @ObservationIgnored
    /// Not private: the original-image request lives in its own extension
    /// file, and it needs the same manager so its requests share the cache and
    /// the cancel table with every other request here.
    let imageManager = PHCachingImageManager()
    /// Final, screen-sized detail renditions. PhotoKit's own cache is useful
    /// while a request is active, but does not guarantee that reopening a page
    /// gets the exact final callback immediately. Keep a small decoded-image
    /// cache so revisits and pager neighbours paint sharp on their first frame.
    @ObservationIgnored
    private let detailImageCache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        // Five pages (current ± 2, FS-02 §8) of two tiers each, iPad-sized.
        cache.countLimit = 16
        cache.totalCostLimit = 220 * 1_024 * 1_024
        return cache
    }()
    /// Final (non-degraded) grid thumbnails, keyed by asset *and* requested
    /// width. Opportunistic delivery paints a soft preview before the sharp
    /// rendition, which is invisible while scrolling but not on a `reloadData`:
    /// cells get reused for different tiles, so every visible cell clears and
    /// re-requests, and the whole grid visibly goes soft and sharpens again —
    /// what the first-paint-to-full-library swap looked like. A cell that finds
    /// its exact rendition here paints sharp synchronously and skips the
    /// request entirely. Sized for a dense screenful plus prefetch headroom.
    @ObservationIgnored
    private let gridThumbnailCache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()
    /// Final, display-sized album hero covers. This is deliberately separate
    /// from grid/detail caches: scrolling or paging must not evict the
    /// On This Day cover that was warmed during app launch.
    @ObservationIgnored
    private let albumCoverImageCache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()
    @ObservationIgnored
    private var isObservingChanges = false
    /// Decoded-neighbour requests in flight, by asset id (FS-02 §8 D6).
    @ObservationIgnored
    private var detailPrefetches: [String: PHImageRequestID] = [:]
    /// Trailing-edge debounce shared by both tokens: iCloud downloads during an
    /// index run fire `photoLibraryDidChange` per asset; bumping a token each
    /// time would trigger a full-library reload per photo.
    @ObservationIgnored
    private var pendingChangeTokenBump: Task<Void, Never>?
    /// Set when any notification coalesced into the pending debounce window was
    /// a structural change, so a content-only change arriving afterwards can't
    /// swallow the `assetChangeToken` bump.
    @ObservationIgnored
    private var pendingStructuralChange = false
    @ObservationIgnored
    private var pendingCollectionChange = false
    /// Assets PhotoKit reported edited since the last debounced bump.
    @ObservationIgnored private var pendingChangedAssetIds: Set<String> = []
    /// PhotoKit gave no diff, or too many changes to list one by one.
    @ObservationIgnored private var pendingEverythingChanged = false
    /// Past this many changed assets in one window, a fresh pass is cheaper
    /// than marking each.
    private nonisolated static let changedAssetsCap = 5_000

    /// What changed in the library for the original-on-device check
    /// (FS-06.10 AC-8), once per debounced bump: the ids of assets edited
    /// (their render may not be here yet), or `nil` when PhotoKit could not
    /// say what changed — then everything is due again.
    @ObservationIgnored var onAssetsChanged: (@MainActor (Set<String>?) -> Void)?
    /// Baseline for classifying changes as structural vs content-only. Must be
    /// seeded before the first notification arrives (see `startObservingChanges`)
    /// — without it every change looks structural.
    @ObservationIgnored
    private(set) var allPhotosFetchResult: PHFetchResult<PHAsset>?
    /// Baseline for spotting album changes, seeded beside `allPhotosFetchResult`
    /// and for the same reason: with no prior result there is nothing to diff
    /// against and every change would look like an album change.
    @ObservationIgnored
    private var albumsFetchResult: PHFetchResult<PHAssetCollection>?
    /// Owns the diffing baselines off the main actor (see `LibraryChangeClassifier`).
    @ObservationIgnored
    private nonisolated let changeClassifier = LibraryChangeClassifier()

    override init() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationState = PhotoAuthorizationState(status)
        super.init()
        Self.logger.log("photo authorization at launch: \(Self.describe(status), privacy: .public)")
        if authorizationState.canReadLibrary {
            startObservingChanges()
        }
        #if canImport(UIKit)
        // iOS asks for memory back: the decoded caches go first, before the
        // system kills the app (FS-02 §8 A4). They refill from PhotoKit.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearDecodedImageCaches() }
        }
        #endif
    }

    /// Drops every decoded image this service holds and the decoded-neighbour
    /// prefetches in flight (FS-02 §8 A4).
    func clearDecodedImageCaches() {
        detailImageCache.removeAllObjects()
        gridThumbnailCache.removeAllObjects()
        albumCoverImageCache.removeAllObjects()
        for id in detailPrefetches.values { imageManager.cancelImageRequest(id) }
        detailPrefetches.removeAll()
    }

    deinit {
        if isObservingChanges {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    // MARK: Authorization

    /// Reads the permission again — the user may have changed it in System
    /// Settings while the app stayed open. Returns true when it changed.
    @discardableResult
    func refreshAuthorization() -> Bool {
        let state = PhotoAuthorizationState(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        guard state != authorizationState else { return false }
        authorizationState = state
        if state.canReadLibrary, !isObservingChanges {
            startObservingChanges()
            refreshAllPhotos()
        }
        return true
    }

    /// Requests read-write access (write needed for favorite toggling).
    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationState = PhotoAuthorizationState(status)
        Self.logger.log("photo authorization after request: \(Self.describe(status), privacy: .public)")
        if authorizationState.canReadLibrary {
            startObservingChanges()
            refreshAllPhotos()
        }
    }

    /// Human-readable `PHAuthorizationStatus` for logs (raw values alone are
    /// opaque: 0 notDetermined, 1 restricted, 2 denied, 3 authorized, 4 limited).
    private static func describe(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined(0)"
        case .restricted: return "restricted(1)"
        case .denied: return "denied(2)"
        case .authorized: return "authorized(3)"
        case .limited: return "limited(4)"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    #if canImport(UIKit)
    /// Presents the limited-library picker (Limited access → Manage).
    func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            var presenter = scene.keyWindow?.rootViewController
        else { return }
        // From whatever is on top: a full-screen editor (the Video Studio's
        // Media panel) is itself presented, and the root cannot present a
        // second controller over it.
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
    }
    #else
    /// The Mac has no limited-library picker: access is all or nothing, set
    /// in System Settings › Privacy & Security › Photos.
    func presentLimitedLibraryPicker() {}
    #endif

    // MARK: Fetching

    /// Predicate for media the app handles everywhere — browsing surfaces
    /// (Library grid, Albums, On This Day, detail viewer) **and** the index:
    /// photos **and** videos. Videos are indexed as rows with no EXIF (the
    /// EXIF pass skips them, see `IndexPipeline.shouldSkipExifRead`), so they
    /// count toward totals and appear in the grid but carry no gear metadata —
    /// gear charts fold them into their "Unknown" bucket.
    nonisolated static var browsableMediaPredicate: NSPredicate {
        NSPredicate(
            format: "mediaType = %d OR mediaType = %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
    }

    /// Fetches all browsable assets (photos + videos) sorted by creation
    /// date, newest first.
    @discardableResult
    func refreshAllPhotos() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = Self.browsableMediaPredicate
        let result = PHAsset.fetchAssets(with: options)
        allPhotosFetchResult = result
        changeClassifier.setAllPhotos(result)
        return result
    }

    /// The playable `AVAsset` behind a video `PHAsset` (downloading from
    /// iCloud when needed). Shared by the metadata reader's file-info section
    /// and the Video Studio's source loader.
    nonisolated static func requestAVAsset(for asset: PHAsset) async -> AVAsset? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
    }

    /// Fetches specific assets by local identifier, preserving request order.
    nonisolated static func fetchAssets(ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        // A burst's other frames are left out of a fetch by default, even
        // when asked for by id — the Duplicates frame picker then saw one
        // frame of a 2-frame burst and showed its empty state.
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
        var byId: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            byId[asset.localIdentifier] = asset
        }
        return ids.compactMap { byId[$0] }
    }

    // MARK: Thumbnails

    /// What one `requestThumbnail` callback carried. `.opportunistic` delivery
    /// fires a cheap preview first, then the final; the final is only *sharp*
    /// when it has the pixels the cell asked for.
    struct ThumbnailDelivery {
        /// PhotoKit's own flag: a preview that a later callback will replace.
        let isDegraded: Bool
        /// Final callback with (near) the requested pixel size. A local-only
        /// request for an iCloud-optimized asset ends with a non-degraded
        /// callback that is just the small proxy on device — displayable, but
        /// not the rendition the cell wanted.
        let isSharp: Bool
        /// The request finished: no further callback will come.
        var isFinal: Bool { !isDegraded }
    }

    /// Requests a thumbnail sized for a grid cell. The handler may fire twice
    /// (degraded then final) because of `.opportunistic` delivery.
    ///
    /// Grid cells run a three-pass ladder, cheapest first, each pass only when
    /// the previous final was not `isSharp`:
    /// 1. `.fast`, local — PhotoKit hands over its nearest ready-made rendition
    ///    (same size or slightly larger) without a resample. This is what
    ///    Photos and Apple's PhotoKit sample use for grids, and it is the pass
    ///    that runs while scrolling, so it must match `startCachingThumbnails`.
    /// 2. `.exact`, local — once the grid is at rest, for tiles whose fast
    ///    rendition came up short.
    /// 3. `.exact`, network — the on-device best was an Optimize Storage proxy.
    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        resizeMode: PHImageRequestOptionsResizeMode = .exact,
        allowNetwork: Bool = true,
        completion: @escaping (PlatformImage?, ThumbnailDelivery) -> Void
    ) -> PHImageRequestID {
        // A network pass is only started when few are already running. On a
        // library kept in iCloud, a screenful of Optimize-Storage proxies used
        // to start a download each the moment scrolling stopped — dozens at
        // once, competing with each other and with whatever the user does
        // next. The tile stays soft until a slot frees up and the next
        // scroll-stop asks again, which is the same thing Photos does.
        if allowNetwork, !Self.networkThumbnailGate.tryAcquire() {
            Task { @MainActor in
                completion(nil, ThumbnailDelivery(isDegraded: false, isSharp: false))
            }
            return PHInvalidImageRequestID
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = resizeMode
        options.isNetworkAccessAllowed = allowNetwork
        let requestedAt = ContinuousClock.now
        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { [weak self] image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isSharp = !isDegraded && image.map {
                Self.hasThumbnailResolution($0, for: asset, targetSize: targetSize, contentMode: contentMode)
            } ?? false
            if !isDegraded, allowNetwork {
                Self.networkThumbnailGate.release()
            }
            if !isDegraded {
                // A download that genuinely failed — offline, signed out of
                // iCloud, asset gone — reads the same as "still not sharp"
                // otherwise, and the tile would stay soft for the session with
                // nothing recorded.
                if info?[PHImageErrorKey] != nil {
                    Self.thumbnailProbe.recordNetworkFailure()
                }
                Self.thumbnailProbe.recordFinal(
                    latency: requestedAt.duration(to: .now),
                    resizeMode: resizeMode,
                    allowNetwork: allowNetwork,
                    isSharp: isSharp
                )
            }
            // Opportunistic PhotoKit callbacks may fire before requestImage
            // returns. Always defer state delivery so callers can first store
            // the returned request ID and cancellation remains correct.
            Task { @MainActor in
                // Only a rendition with the cell's pixels goes in: caching the
                // small local proxy of an Optimize-Storage asset as the "final"
                // for this width kept that tile soft for the life of the cache,
                // since a hit skips the request entirely.
                // Grid-sized only: a viewer's screen- or full-size picture
                // (PHImageManagerMaximumSize is −1×−1) would flush every
                // tile out of the 48 MB cache under a key no grid reads.
                let cost = image.map { Int($0.size.width * $0.size.height * $0.scale * $0.scale * 4) } ?? 0
                if let image, isSharp, targetSize.width > 0, cost <= 2 * 1_024 * 1_024 {
                    self?.gridThumbnailCache.setObject(
                        image,
                        forKey: Self.gridThumbnailKey(asset.localIdentifier, width: targetSize.width),
                        cost: cost
                    )
                }
                completion(image, ThumbnailDelivery(isDegraded: isDegraded, isSharp: isSharp))
            }
        }
    }

    /// Request-to-final latency, aggregated per ladder pass and logged every
    /// 100 finals (`category: thumbnails`, debug level). Reading the summary on
    /// device answers whether prefetch hits (fast/local finals in single-digit
    /// ms) and how often tiles fall through to the exact and network passes.
    private static let thumbnailProbe = ThumbnailLatencyProbe()

    /// How many iCloud thumbnail downloads may be in flight at once.
    ///
    /// Four, not one: a single slot makes a screenful of cloud-only photos
    /// fill in one at a time, and not unbounded because a wide iPad grid can
    /// have forty proxies visible at a scroll-stop.
    private static let networkThumbnailGate = ConcurrencyGate(limit: 4)

    private final class ThumbnailLatencyProbe: @unchecked Sendable {
        private struct Bucket {
            var count = 0
            var sharpCount = 0
            var total: Duration = .zero
            var slowest: Duration = .zero
            var summary: String {
                guard count > 0 else { return "0" }
                let mean = total / count
                return "\(count) (sharp \(sharpCount), mean \(Self.milliseconds(mean))ms, max \(Self.milliseconds(slowest))ms)"
            }
            private static func milliseconds(_ duration: Duration) -> Int {
                Int(duration.components.seconds * 1_000)
                    + Int(duration.components.attoseconds / 1_000_000_000_000_000)
            }
        }
        private let lock = NSLock()
        private var fastLocal = Bucket()
        private var exactLocal = Bucket()
        private var network = Bucket()
        /// Downloads that came back with an error rather than an image. Kept
        /// apart from "not sharp": one is a tile waiting for a slot, the other
        /// is a tile that will never sharpen until the network changes.
        private var networkFailures = 0
        private var sinceLog = 0
        private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "thumbnails")

        func recordNetworkFailure() {
            lock.lock()
            defer { lock.unlock() }
            networkFailures += 1
        }

        func recordFinal(
            latency: Duration,
            resizeMode: PHImageRequestOptionsResizeMode,
            allowNetwork: Bool,
            isSharp: Bool
        ) {
            lock.lock()
            defer { lock.unlock() }
            func record(_ bucket: inout Bucket) {
                bucket.count += 1
                if isSharp { bucket.sharpCount += 1 }
                bucket.total += latency
                bucket.slowest = max(bucket.slowest, latency)
            }
            if allowNetwork {
                record(&network)
            } else if resizeMode == .fast {
                record(&fastLocal)
            } else {
                record(&exactLocal)
            }
            sinceLog += 1
            guard sinceLog >= 100 else { return }
            sinceLog = 0
            Self.logger.debug(
                "thumbnail finals — fast/local: \(self.fastLocal.summary, privacy: .public); exact/local: \(self.exactLocal.summary, privacy: .public); network: \(self.network.summary, privacy: .public); network errors: \(self.networkFailures, privacy: .public)"
            )
        }
    }

    /// Image-only convenience for callers that just paint whatever arrives.
    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        allowNetwork: Bool = true,
        completion: @escaping (PlatformImage?) -> Void
    ) -> PHImageRequestID {
        requestThumbnail(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            allowNetwork: allowNetwork
        ) { image, _ in completion(image) }
    }

    /// Whether a thumbnail callback has (within 10%) the pixels the request
    /// asked for, capped by what the asset itself has. Aspect-fill results are
    /// cropped to the target, so only the shorter side is comparable there;
    /// aspect-fit reuses the detail viewer's check.
    private nonisolated static func hasThumbnailResolution(
        _ image: PlatformImage,
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode
    ) -> Bool {
        guard contentMode == .aspectFill else {
            return hasDisplayResolution(image, for: asset, targetSize: targetSize)
        }
        let assetShortSide = CGFloat(min(asset.pixelWidth, asset.pixelHeight))
        guard assetShortSide > 0 else { return true }
        let expectedShortSide = min(min(targetSize.width, targetSize.height), assetShortSide)
        let actualShortSide = min(image.size.width, image.size.height) * image.scale
        return actualShortSide >= expectedShortSide * 0.9
    }

    /// The sharp rendition for this exact cell size, when one was already
    /// delivered. Lets a cell paint on its first frame instead of clearing to
    /// grey and waiting for an opportunistic preview.
    func cachedThumbnail(for assetId: String, width: CGFloat) -> PlatformImage? {
        gridThumbnailCache.object(forKey: Self.gridThumbnailKey(assetId, width: width))
    }

    /// Width is part of the key: a rendition from a different column count is
    /// the wrong number of pixels, and painting it would be the soft tile this
    /// cache exists to avoid.
    private static func gridThumbnailKey(_ assetId: String, width: CGFloat) -> NSString {
        "\(assetId)@\(Int(width.rounded()))" as NSString
    }

    func cancelThumbnailRequest(_ requestId: PHImageRequestID) {
        imageManager.cancelImageRequest(requestId)
    }

    /// Requests a display-sized album hero. Opportunistic delivery lets the
    /// card paint any on-device preview immediately, then replaces it with the
    /// exact rendition. The final image is retained in a dedicated decoded
    /// cache so a launch-time preheat survives unrelated grid/detail traffic.
    func requestAlbumCover(
        for asset: PHAsset,
        targetSize: CGSize,
        allowNetwork: Bool = true,
        completion: @escaping (PlatformImage?) -> Void
    ) -> PHImageRequestID {
        let cacheKey = albumCoverCacheKey(for: asset, targetSize: targetSize)
        if let cached = albumCoverImageCache.object(forKey: cacheKey) {
            Task { @MainActor in completion(cached) }
            return PHInvalidImageRequestID
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = allowNetwork

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if let image,
               !degraded,
               Self.hasAlbumCoverResolution(image, for: asset, targetSize: targetSize) {
                let pixelWidth = image.cgImage?.width ?? Int(image.size.width * image.scale)
                let pixelHeight = image.cgImage?.height ?? Int(image.size.height * image.scale)
                self.albumCoverImageCache.setObject(
                    image,
                    forKey: cacheKey,
                    cost: pixelWidth * pixelHeight * 4
                )
            }
            Task { @MainActor in completion(image) }
        }
    }

    private func albumCoverCacheKey(for asset: PHAsset, targetSize: CGSize) -> NSString {
        let width = Int(targetSize.width.rounded(.up))
        let height = Int(targetSize.height.rounded(.up))
        return "\(asset.localIdentifier)|\(width)x\(height)|album-cover" as NSString
    }

    /// PhotoKit may label the best currently-local proxy as non-degraded even
    /// when it is smaller than the requested hero. It can still be displayed
    /// as a temporary fallback, but must not poison the sharp-cover cache.
    private nonisolated static func hasAlbumCoverResolution(
        _ image: PlatformImage,
        for asset: PHAsset,
        targetSize: CGSize
    ) -> Bool {
        let actual = [
            CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale)),
            CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale)),
        ].sorted()
        let expected = [
            min(CGFloat(asset.pixelWidth), targetSize.width),
            min(CGFloat(asset.pixelHeight), targetSize.height),
        ].sorted()
        return actual[0] >= expected[0] * 0.9
            && actual[1] >= expected[1] * 0.9
    }

    /// Full-screen image for the detail viewer. Preview delivery also has a
    /// separate local-only request (`requestBestLocalImage`); this opportunistic
    /// request may return an immediate degraded rendition and then the exact
    /// final. Callers must use the degraded flag to promote only the final.
    /// Final screen-sized renditions are retained in a small decoded cache;
    /// full-original requests are not.
    ///
    /// `progress` reports iCloud download 0…1. The completion Bool remains the
    /// PhotoKit degraded flag lets callers distinguish the temporary and final
    /// callbacks.
    func requestDetailImage(
        for asset: PHAsset,
        targetSize: CGSize,
        allowNetwork: Bool = true,
        progress: @escaping (Double) -> Void,
        completion: @escaping (PlatformImage?, Bool) -> Void
    ) -> PHImageRequestID {
        let cacheKey = detailCacheKey(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            tier: .displayFinal
        )
        if let cacheKey, let cached = detailImageCache.object(forKey: cacheKey) {
            // Keep the completion asynchronous like PhotoKit. This also lets
            // the caller store PHInvalidImageRequestID before clearing it.
            Task { @MainActor in completion(cached, false) }
            return PHInvalidImageRequestID
        }

        let options = PHImageRequestOptions()
        // The proven detail path is opportunistic: PhotoKit can return an
        // already-local display rendition immediately, then the exact final
        // callback. The page's quality tiers prevent that early result from
        // ever overwriting the final one.
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        // A screen-sized `targetSize` (network on) streams only iCloud's
        // screen-sized derivative — fast. Pass `PHImageManagerMaximumSize` to
        // pull the multi-MB original (zoom-to-pixel-peep). `allowNetwork: false`
        // restricts to local renditions.
        options.isNetworkAccessAllowed = allowNetwork
        options.progressHandler = { value, _, _, _ in
            Task { @MainActor in progress(value) }
        }
        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let hasDisplayPixels = image.map {
                Self.hasDisplayResolution($0, for: asset, targetSize: targetSize)
            } ?? false
            guard let image, !degraded else {
                Task { @MainActor in completion(image, degraded) }
                return
            }
            // The final is decoded before it reaches the view, never at draw
            // time on the main thread (FS-02 §8 A2).
            Self.decodedForDisplay(image) { decoded in
                if hasDisplayPixels, let cacheKey {
                    self.detailImageCache.setObject(decoded, forKey: cacheKey, cost: Self.decodedCost(decoded))
                }
                Task { @MainActor in completion(decoded, false) }
            }
        }
    }

    /// Preheats local screen-sized renditions for the visible detail page and
    /// its immediate pager neighbours. Network remains disabled: swiping must
    /// not silently download several iCloud originals.
    func startCachingDetailImages(for assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: Self.detailCachingOptions
        )
    }

    func stopCachingDetailImages(for assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: Self.detailCachingOptions
        )
    }

    /// Decoded neighbours (FS-02 §8 D6, A3): the best local rendition of each
    /// asset, decoded off the main thread and kept in the detail cache under
    /// the same key `requestBestLocalImage` reads — so a page swiped to paints
    /// sharp on its first frame, and one swiped back to after its own request
    /// was cancelled is still there. Assets no longer wanted are cancelled.
    /// Network stays off: swiping never downloads originals.
    func prefetchDecodedDetailImages(for assets: [PHAsset], targetSize: CGSize) {
        let wanted = Set(assets.map(\.localIdentifier))
        for (id, request) in detailPrefetches where !wanted.contains(id) {
            imageManager.cancelImageRequest(request)
            detailPrefetches[id] = nil
        }
        for asset in assets where detailPrefetches[asset.localIdentifier] == nil {
            guard let key = detailCacheKey(for: asset, targetSize: targetSize, contentMode: .aspectFit, tier: .local),
                  detailImageCache.object(forKey: key) == nil
            else { continue }
            let id = asset.localIdentifier
            let options = Self.detailCachingOptions
            detailPrefetches[id] = imageManager.requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard let image, !degraded else { return }
                Self.decodedForDisplay(image) { decoded in
                    self.detailImageCache.setObject(decoded, forKey: key, cost: Self.decodedCost(decoded))
                    Task { @MainActor in self.detailPrefetches[id] = nil }
                }
            }
        }
    }

    /// Decodes `image` so drawing it costs nothing: on its own queue when
    /// called on the main thread, in place otherwise (PhotoKit's queues).
    nonisolated static func decodedForDisplay(_ image: PlatformImage, then deliver: @escaping (PlatformImage) -> Void) {
        #if canImport(UIKit)
        let work = { deliver(image.preparingForDisplay() ?? image) }
        if Thread.isMainThread {
            // The image and its continuation hop one queue and are touched
            // there alone; the box says so to the checker.
            let job = DecodeHopBox(work)
            DispatchQueue.global(qos: .userInitiated).async { job.value() }
        } else {
            work()
        }
        #else
        deliver(image)
        #endif
    }

    nonisolated static func decodedCost(_ image: PlatformImage) -> Int {
        #if canImport(UIKit)
        Int(image.size.width * image.scale) * Int(image.size.height * image.scale) * 4
        #else
        Int(image.size.width) * Int(image.size.height) * 4
        #endif
    }

    /// Sharpest LOCAL rendition, no network — the device-sized derivative
    /// "Optimize iPhone Storage" keeps on disk, exactly what the Photos app
    /// shows full-screen even offline. `requestImage` works off renditions,
    /// so `.highQualityFormat` returns the best on-device version (NOT nil like
    /// `requestImageDataAndOrientation`, which reads the original file — absent
    /// for offloaded assets). Network off → a single non-degraded delivery.
    func requestBestLocalImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFit,
        completion: @escaping (PlatformImage?) -> Void
    ) -> PHImageRequestID {
        let cacheKey = detailCacheKey(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            tier: .local
        )
        if let cacheKey, let cached = detailImageCache.object(forKey: cacheKey) {
            Task { @MainActor in completion(cached) }
            return PHInvalidImageRequestID
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard let image, !degraded else {
                Task { @MainActor in completion(image) }
                return
            }
            Self.decodedForDisplay(image) { decoded in
                if let cacheKey {
                    self.detailImageCache.setObject(decoded, forKey: cacheKey, cost: Self.decodedCost(decoded))
                }
                Task { @MainActor in completion(decoded) }
            }
        }
    }

    /// Reads the actual current-version image bytes only when they already
    /// exist on this device, then downsamples with ImageIO to the display
    /// target. Unlike `requestImage`, this path cannot confuse a locally cached
    /// grid rendition with the local original. Network stays disabled.
    func requestLocalOriginalScreenImage(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (PlatformImage?) -> Void
    ) -> PHImageRequestID {
        let cacheKey = detailCacheKey(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            tier: .localOriginal
        )
        if let cacheKey, let cached = detailImageCache.object(forKey: cacheKey) {
            Task { @MainActor in completion(cached) }
            return PHInvalidImageRequestID
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.version = .current
        let maxPixelSize = Self.aspectFitMaxPixel(for: asset, targetSize: targetSize)

        return imageManager.requestImageDataAndOrientation(
            for: asset,
            options: options
        ) { data, _, _, _ in
            guard let data,
                  let image = Self.downsampleImageData(data, maxPixelSize: maxPixelSize)
            else {
                Task { @MainActor in completion(nil) }
                return
            }
            if let cacheKey {
                let pixelWidth = image.cgImage?.width ?? Int(image.size.width * image.scale)
                let pixelHeight = image.cgImage?.height ?? Int(image.size.height * image.scale)
                self.detailImageCache.setObject(
                    image,
                    forKey: cacheKey,
                    cost: pixelWidth * pixelHeight * 4
                )
            }
            Task { @MainActor in completion(image) }
        }
    }

    /// Prefetch thumbnails for assets about to scroll on screen
    /// (UICollectionViewDataSourcePrefetching). Must use the same options as
    /// `requestThumbnail` so the cache actually hits.
    func startCachingThumbnails(for assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: Self.cachingOptions
        )
    }

    /// Cancels prefetch for assets that scrolled away before display.
    func stopCachingThumbnails(for assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: Self.cachingOptions
        )
    }

    /// Drops the whole prefetch cache — call when the grid's cell size
    /// changes (density step), old sizes are useless then.
    func stopCachingAllThumbnails() {
        imageManager.stopCachingImagesForAllAssets()
    }

    /// Identical to the grid's scrolling pass (`requestThumbnail` with `.fast`,
    /// local-only, opportunistic). `PHCachingImageManager` keys its cache on
    /// the request options too, so a prefetch with different delivery or
    /// resize settings than the cell's request is decode work the cell never
    /// benefits from — the earlier `.highQualityFormat` + `.exact` prefetch
    /// against an `.opportunistic` request was exactly that. Apple's PhotoKit
    /// sample passes the same (nil) options to both calls for this reason.
    private static var cachingOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        return options
    }

    private static var detailCachingOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        return options
    }

    /// A local rendition may report non-degraded even when it is only the best
    /// low-resolution file currently on device. It must never satisfy a later
    /// network-final lookup at the same target size.
    private enum DetailCacheTier: String {
        case local
        case localOriginal
        case displayFinal
    }

    /// Full originals can be tens or hundreds of MB decoded, so only finite
    /// display-sized requests participate in the decoded cache.
    private func detailCacheKey(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        tier: DetailCacheTier
    ) -> NSString? {
        // `PHImageManagerMaximumSize` is (−1, −1): it must not pass as a
        // finite display size, or a zoom's full original (hundreds of MB
        // decoded) lands here and pushes every screen image out (FS-02 §8 A1).
        guard Self.isCacheableDetailSize(targetSize) else { return nil }
        let width = Int(targetSize.width.rounded(.up))
        let height = Int(targetSize.height.rounded(.up))
        let mode = contentMode == .aspectFill ? "fill" : "fit"
        return "\(asset.localIdentifier)|\(width)x\(height)|\(mode)|\(tier.rawValue)" as NSString
    }

    /// A finite, positive display size — never `PHImageManagerMaximumSize`.
    nonisolated static func isCacheableDetailSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite
            && size.width > 0 && size.height > 0
            && size.width < 100_000 && size.height < 100_000
    }

    private nonisolated static func aspectFitMaxPixel(
        for asset: PHAsset,
        targetSize: CGSize
    ) -> CGFloat {
        let sourceWidth = CGFloat(asset.pixelWidth)
        let sourceHeight = CGFloat(asset.pixelHeight)
        guard sourceWidth > 0, sourceHeight > 0,
              targetSize.width > 0, targetSize.height > 0
        else { return max(targetSize.width, targetSize.height) }
        let scale = min(
            1,
            min(targetSize.width / sourceWidth, targetSize.height / sourceHeight)
        )
        return ceil(max(sourceWidth * scale, sourceHeight * scale))
    }

    private nonisolated static func downsampleImageData(
        _ data: Data,
        maxPixelSize: CGFloat
    ) -> PlatformImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else { return nil }
        return PlatformImage(cgImage: cgImage)
    }

    private nonisolated static func hasDisplayResolution(
        _ image: PlatformImage,
        for asset: PHAsset,
        targetSize: CGSize
    ) -> Bool {
        let sourceWidth = CGFloat(asset.pixelWidth)
        let sourceHeight = CGFloat(asset.pixelHeight)
        guard sourceWidth > 0, sourceHeight > 0 else { return true }
        let fitScale = min(
            1,
            min(targetSize.width / sourceWidth, targetSize.height / sourceHeight)
        )
        let expected = [
            sourceWidth * fitScale,
            sourceHeight * fitScale,
        ].sorted()
        let actual = [
            image.size.width * image.scale,
            image.size.height * image.scale,
        ].sorted()
        return actual[0] >= expected[0] * 0.9
            && actual[1] >= expected[1] * 0.9
    }

    // MARK: Video

    /// `AVPlayerItem` for the detail viewer's video pages.
    ///
    /// Deliberately a `Result` rather than an optional: PhotoKit returns `nil`
    /// for a cancelled request, a genuine failure, and an iCloud item it cannot
    /// serve, and the viewer must distinguish them — the earlier optional-based
    /// call site silently dropped every one of those, leaving the page on a
    /// spinner forever. `progress` reports the iCloud download 0…1 so the page
    /// can show the same determinate ring the image path uses.
    ///
    /// Cancelled requests report nothing at all; the caller has already torn
    /// its state down by then.
    func requestPlayerItem(
        for asset: PHAsset,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<AVPlayerItem, Error>) -> Void
    ) -> PHImageRequestID {
        let options = PHVideoRequestOptions()
        // Videos can only come from iCloud as a whole file, so unlike the image
        // path there is no cheap local derivative to fall back to: network must
        // be allowed or an offloaded clip is simply unplayable.
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        options.version = .current
        options.progressHandler = { value, _, _, _ in
            Task { @MainActor in progress(value) }
        }
        return imageManager.requestPlayerItem(
            forVideo: asset,
            options: options
        ) { item, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            guard !cancelled else { return }
            let error = info?[PHImageErrorKey] as? Error
            // Hop to the main actor like every other request here, so a
            // synchronous PhotoKit callback cannot beat the caller storing the
            // request id it would need in order to cancel.
            Task { @MainActor in
                if let item {
                    completion(.success(item))
                } else {
                    completion(.failure(error ?? PhotoVideoError.unavailable))
                }
            }
        }
    }

    /// Cancels an in-flight `requestPlayerItem`. Same underlying request table
    /// as the image requests, hence the shared cancel call.
    func cancelVideoRequest(_ requestId: PHImageRequestID) {
        guard requestId != PHInvalidImageRequestID else { return }
        imageManager.cancelImageRequest(requestId)
    }

    // MARK: Favorites

    /// Toggles the PhotoKit favorite flag. PhotoKit is the source of truth;
    /// the database column is synced afterwards by the caller.
    func setFavorite(_ isFavorite: Bool, for asset: PHAsset) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = isFavorite
        }
    }

    // MARK: Deletion

    /// Deletes assets from the photo library (they move to Recently Deleted).
    /// PhotoKit shows its own confirmation dialog; if the user cancels,
    /// this throws `PHPhotosError.userCancelled`.
    func deleteAssets(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
        // Every deletion the app makes passes here, so this is where the
        // photos' stars and flags go with them (FS-01.12 §4).
        await onAssetsDeleted?(assets.map(\.localIdentifier))
    }

    /// FS-19.07 §9: asks the server about photos that rely on it before
    /// they are deleted. Set once by the composition root; nil in previews.
    @ObservationIgnored
    var deletionGate: PhotoDeletionGate?

    /// `deleteAssets` through the gate, for the entry points with no alerts
    /// of their own: photos not on a server, or confirmed there, are
    /// deleted; the rest are kept and reported by `PhotoDeletionGate.Kept`.
    func deleteAssetsCheckingServer(_ assets: [PHAsset]) async throws {
        guard let deletionGate, !assets.isEmpty else { return try await deleteAssets(assets) }
        let outcome = await deletionGate.check(photoIds: assets.map(\.localIdentifier))
        let allowed = Set(outcome.deletable)
        try await deleteAssets(assets.filter { allowed.contains($0.localIdentifier) })
        if allowed.count < assets.count { throw PhotoDeletionGate.Kept(outcome: outcome) }
    }

    /// Told the ids of assets PhotoKit has just deleted at the app's request.
    /// Set once by the composition root.
    @ObservationIgnored
    var onAssetsDeleted: (@MainActor ([String]) async -> Void)?

    // MARK: Import

    /// Copies a file (e.g. one read off an SD card / USB volume) into the photo
    /// library as a brand-new asset, returning its local identifier. `isVideo`
    /// picks the PhotoKit resource type (`.video` vs `.photo`). The source file
    /// is left untouched (`shouldMoveFile = false`) — the card is treated as
    /// read-only. Requires `.readWrite` authorization (already requested at
    /// launch). The new asset triggers `photoLibraryDidChange`, so the normal
    /// `IndexPipeline` picks it up without an explicit index call.
    func importFile(at url: URL, isVideo: Bool) async throws -> String {
        var placeholderId: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            // Preserve the card's filename so file-type (RAW/JPG) classification
            // and the detail viewer show the original name.
            options.originalFilename = url.lastPathComponent
            request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: options)
            placeholderId = request.placeholderForCreatedAsset?.localIdentifier
        }
        guard let placeholderId else { throw PhotoImportError.creationFailed }
        return placeholderId
    }

    /// Saves already-encoded image bytes as a new library asset — used by the
    /// video viewer's "Save Frame to Photos". Data rather than a file URL so no
    /// temporary file has to be written and cleaned up. Requires `.readWrite`
    /// authorization (requested at launch), and the new asset reaches the index
    /// through the normal `photoLibraryDidChange` path.
    /// Full image-property dictionary (EXIF/TIFF/GPS/…) of an asset's original,
    /// for carrying metadata into an exported collage. Pulls the original data
    /// (network allowed), so use only on an explicit opt-in.
    func imageProperties(for asset: PHAsset) async -> [CFString: Any]? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            options.isSynchronous = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard let data,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: properties)
            }
        }
    }

    /// Saves a file that is already on disk as a new library asset, and moves
    /// it rather than copying.
    ///
    /// Separate from `saveImage(_:filename:)`, which takes bytes, because a
    /// panorama is not something that can be held as bytes: a couple of hundred
    /// megapixels is a file that was written a strip at a time and must never
    /// be read back into memory whole just to hand it over
    /// ([FS-14.02 §6](../../../docs/02-functional-spec/FS-14-panorama/02-stitching-pipeline.md)).
    ///
    /// `shouldMoveFile` is true here and false in `importFile`, and the
    /// difference is whose file it is: an import is reading somebody's memory
    /// card, which must be left alone, while this is our own scratch file and
    /// letting PhotoKit take it saves copying a few hundred megabytes and
    /// deleting them afterwards.
    func saveImageFile(at url: URL, filename: String) async throws -> String {
        var placeholderId: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = filename
            options.shouldMoveFile = true
            request.addResource(with: .photo, fileURL: url, options: options)
            placeholderId = request.placeholderForCreatedAsset?.localIdentifier
        }
        guard let placeholderId else { throw PhotoImportError.creationFailed }
        return placeholderId
    }

    func saveImage(_ data: Data, filename: String) async throws -> String {
        var placeholderId: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = filename
            request.addResource(with: .photo, data: data, options: options)
            placeholderId = request.placeholderForCreatedAsset?.localIdentifier
        }
        guard let placeholderId else { throw PhotoImportError.creationFailed }
        return placeholderId
    }

    // MARK: Collections

    /// Every user-created album, newest title order as PhotoKit returns them.
    /// Smart albums and shared albums are excluded — "Add to Collection" only
    /// targets albums the user can freely add to.
    nonisolated static func fetchUserAlbums() -> [PHAssetCollection] {
        var albums: [PHAssetCollection] = []
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        result.enumerateObjects { collection, _, _ in albums.append(collection) }
        return albums
    }

    /// Creates a new user album and returns its freshly-fetched collection.
    func createAlbum(named name: String) async throws -> PHAssetCollection {
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        }
        guard let id = placeholder?.localIdentifier,
              let collection = PHAssetCollection.fetchAssetCollections(
                  withLocalIdentifiers: [id], options: nil
              ).firstObject
        else { throw PhotoImportError.creationFailed }
        return collection
    }

    /// Appends assets to an existing user album. PhotoKit keeps membership a set,
    /// so re-adding an already-present asset is a harmless no-op.
    func addAssets(_ assets: [PHAsset], to collection: PHAssetCollection) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            request.addAssets(assets as NSArray)
        }
    }

    // MARK: Duplicate

    /// Duplicates each asset as a brand-new library item, preserving every
    /// resource (RAW+JPEG pairs, Live Photo video, original filenames) by copying
    /// the source resources verbatim — no re-encode. iCloud-only originals are
    /// downloaded (`isNetworkAccessAllowed`); an asset whose resources all fail to
    /// stage is skipped rather than aborting the batch. Returns how many were
    /// created. The new assets reach the index through `photoLibraryDidChange`.
    func duplicateAssets(_ assets: [PHAsset]) async throws -> Int {
        guard !assets.isEmpty else { return 0 }
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotdex-duplicate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        var created = 0
        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            guard !resources.isEmpty else { continue }
            var staged: [(type: PHAssetResourceType, filename: String, url: URL)] = []
            for resource in resources {
                let fileURL = stagingDir.appendingPathComponent(
                    UUID().uuidString + "-" + resource.originalFilename
                )
                if await writeResource(resource, to: fileURL) {
                    staged.append((resource.type, resource.originalFilename, fileURL))
                }
            }
            guard !staged.isEmpty else { continue }
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                for item in staged {
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = item.filename
                    options.shouldMoveFile = false
                    request.addResource(with: item.type, fileURL: item.url, options: options)
                }
            }
            created += 1
        }
        return created
    }

    /// Writes one `PHAssetResource` to `url`, allowing an iCloud download.
    /// Returns whether it succeeded (a failed resource is dropped from the copy).
    private nonisolated func writeResource(_ resource: PHAssetResource, to url: URL) async -> Bool {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    // MARK: Change observation

    /// Publishes an asset created by ShotDex immediately instead of waiting for
    /// PhotoKit's debounced observer callback. The direct index has already
    /// completed before this is called, so query-backed grids and PhotoKit-backed
    /// grids can both reload with a complete row before the save UI dismisses.
    func publishAppCreatedAsset() {
        // Advance the structural-classification baseline to include the new
        // asset. A later PhotoKit callback remains a harmless safety-net bump.
        refreshAllPhotos()
        libraryChangeToken &+= 1
        assetChangeToken &+= 1
    }

    /// Re-reads the album baseline and returns it. Fetching every user album
    /// is lazy in PhotoKit — the result is a promise, not a list — so this is
    /// cheap enough to do on every album change.
    @discardableResult
    func refreshAlbums() -> PHFetchResult<PHAssetCollection> {
        let result = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        )
        albumsFetchResult = result
        changeClassifier.setAlbums(result)
        return result
    }

    private func startObservingChanges() {
        guard !isObservingChanges else { return }
        PHPhotoLibrary.shared().register(self)
        isObservingChanges = true
        // Seed the classification baseline here, not only after an
        // authorization request: on every launch after the first, `init`
        // starts observation with no prior fetch result, and without one
        // `photoLibraryDidChange` has to treat every change as structural.
        // Cheap — `PHFetchResult` is lazy, nothing is materialized.
        refreshAllPhotos()
        refreshAlbums()
    }
}

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // The diff runs here, on PhotoKit's own background queue, not on the
        // main actor: `changeDetails(for:)` over the whole library plus one
        // per changed asset took the main thread for seconds when an iPad
        // came back after hours and iCloud delivered its backlog — taps on
        // the Albums tab went nowhere until it finished (user 2026-11-14).
        let outcome = changeClassifier.classify(changeInstance, editCap: Self.changedAssetsCap)
        Task { @MainActor in
            self.pendingStructuralChange = self.pendingStructuralChange || outcome.structural
            self.pendingCollectionChange = self.pendingCollectionChange || outcome.collections
            if self.onAssetsChanged != nil, !self.pendingEverythingChanged {
                if outcome.everythingChanged
                    || self.pendingChangedAssetIds.count + outcome.editedAssetIds.count > Self.changedAssetsCap {
                    self.pendingEverythingChanged = true
                    self.pendingChangedAssetIds = []
                } else {
                    self.pendingChangedAssetIds.formUnion(outcome.editedAssetIds)
                }
            }
            // Both tokens share one trailing-edge debounce: iCloud downloads
            // during an index run fire a change per asset, and a full-library
            // reload per photo is what made the grid flicker and the device
            // heat up. Consumers see ≤1 bump/s.
            guard self.pendingChangeTokenBump == nil else { return }
            self.pendingChangeTokenBump = Task { @MainActor in
                defer {
                    self.pendingChangeTokenBump = nil
                    self.pendingStructuralChange = false
                    self.pendingCollectionChange = false
                }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.libraryChangeToken += 1
                if self.pendingEverythingChanged {
                    self.onAssetsChanged?(nil)
                } else if !self.pendingChangedAssetIds.isEmpty {
                    self.onAssetsChanged?(self.pendingChangedAssetIds)
                }
                self.pendingEverythingChanged = false
                self.pendingChangedAssetIds = []
                // PhotoKit also reports content-only changes when an
                // iCloud/local rendition is downloaded or cached, or a
                // favorite is toggled. Those must not reload the grid or
                // launch a fresh index pass after closing Detail.
                if self.pendingStructuralChange {
                    self.assetChangeToken += 1
                }
                if self.pendingCollectionChange {
                    self.collectionChangeToken += 1
                }
            }
        }
    }

}

/// What the Collections tab watches: the browsable asset list, and the set of
/// albums. Separate counters because they answer different questions and an
/// album created with no photos in it moves only the second.
struct LibraryChangeTokens: Hashable, Sendable {
    let asset: Int
    let collection: Int
}

extension PhotoAuthorizationState {
    /// "Full Access", "Limited Access"… — Settings and the Sources rows.
    var title: String {
        switch self {
        case .notDetermined: String(localized: "Not Requested", comment: "Settings → Photo Library: photo access not asked for yet")
        case .authorized: String(localized: "Full Access", comment: "Settings → Photo Library: photo access")
        case .limited: String(localized: "Limited Access", comment: "Settings → Photo Library: photo access")
        case .denied: String(localized: "Denied", comment: "Settings → Photo Library: photo access")
        case .restricted: String(localized: "Restricted", comment: "Settings → Photo Library: photo access")
        }
    }
}

/// Carries a value across one queue hop the checker cannot prove safe — used
/// where exactly one queue touches it after the hop.
struct DecodeHopBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}


/// The structural / album / edited classification of a `PHChange`, done off
/// the main actor. Holds the two baselines it diffs against on one serial
/// queue: the main actor hands new baselines over without waiting, and each
/// change is classified against the baseline the previous one left.
final class LibraryChangeClassifier: @unchecked Sendable {
    struct Outcome: Sendable {
        /// Membership or order of the browsable photos changed.
        var structural = false
        /// The album list changed (one created, removed, renamed, or filled).
        var collections = false
        /// No baseline, no incremental diff, or more edits than the cap.
        var everythingChanged = false
        /// Assets whose picture changed (an edit, a revert) — not a favourite or a hide.
        var editedAssetIds: Set<String> = []
    }

    private let queue = DispatchQueue(label: "com.hoangtuan.shotdex.photokit-changes", qos: .utility)
    private var allPhotos: PHFetchResult<PHAsset>?
    private var albums: PHFetchResult<PHAssetCollection>?

    func setAllPhotos(_ result: PHFetchResult<PHAsset>) {
        queue.async { self.allPhotos = result }
    }

    func setAlbums(_ result: PHFetchResult<PHAssetCollection>) {
        queue.async { self.albums = result }
    }

    /// Both baselines always advance: a later change read against a stale
    /// one is lost.
    func classify(_ change: PHChange, editCap: Int) -> Outcome {
        queue.sync {
            var outcome = Outcome()
            if let current = allPhotos {
                if let details = change.changeDetails(for: current) {
                    allPhotos = details.fetchResultAfterChanges
                    if details.hasIncrementalChanges {
                        outcome.structural = details.insertedIndexes?.isEmpty == false
                            || details.removedIndexes?.isEmpty == false
                            || details.hasMoves
                        let changed = details.changedObjects
                        if changed.count > editCap {
                            outcome.everythingChanged = true
                        } else {
                            for asset in changed where change.changeDetails(for: asset)?.assetContentChanged ?? true {
                                outcome.editedAssetIds.insert(asset.localIdentifier)
                            }
                        }
                    } else {
                        outcome.structural = true
                        outcome.everythingChanged = true
                    }
                }
            } else {
                // No baseline yet (authorization not granted when observation
                // started): cannot classify, so assume the list moved.
                outcome.structural = true
                outcome.everythingChanged = true
            }
            if let current = albums {
                if let details = change.changeDetails(for: current) {
                    albums = details.fetchResultAfterChanges
                    outcome.collections = !details.hasIncrementalChanges
                        || details.insertedIndexes?.isEmpty == false
                        || details.removedIndexes?.isEmpty == false
                        || details.changedIndexes?.isEmpty == false
                        || details.hasMoves
                }
            } else {
                outcome.collections = true
            }
            return outcome
        }
    }
}
