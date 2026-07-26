import AVFoundation
import Foundation
import ImageIO
import Photos
import PhotosUI
import UIKit
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

    @ObservationIgnored
    private let imageManager = PHCachingImageManager()
    /// Final, screen-sized detail renditions. PhotoKit's own cache is useful
    /// while a request is active, but does not guarantee that reopening a page
    /// gets the exact final callback immediately. Keep a small decoded-image
    /// cache so revisits and pager neighbours paint sharp on their first frame.
    @ObservationIgnored
    private let detailImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12
        cache.totalCostLimit = 160 * 1_024 * 1_024
        return cache
    }()
    /// Final, display-sized album hero covers. This is deliberately separate
    /// from grid/detail caches: scrolling or paging must not evict the
    /// On This Day cover that was warmed during app launch.
    @ObservationIgnored
    private let albumCoverImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()
    @ObservationIgnored
    private var isObservingChanges = false
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
    /// Baseline for classifying changes as structural vs content-only. Must be
    /// seeded before the first notification arrives (see `startObservingChanges`)
    /// — without it every change looks structural.
    @ObservationIgnored
    private(set) var allPhotosFetchResult: PHFetchResult<PHAsset>?

    override init() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        self.authorizationState = PhotoAuthorizationState(status)
        super.init()
        Self.logger.log("photo authorization at launch: \(Self.describe(status), privacy: .public)")
        if authorizationState.canReadLibrary {
            startObservingChanges()
        }
    }

    deinit {
        if isObservingChanges {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    // MARK: Authorization

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

    /// Presents the limited-library picker (Limited access → Manage).
    func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let rootViewController = scene.keyWindow?.rootViewController
        else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)
    }

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
        return result
    }

    /// Fetches specific assets by local identifier, preserving request order.
    nonisolated static func fetchAssets(ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byId: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            byId[asset.localIdentifier] = asset
        }
        return ids.compactMap { byId[$0] }
    }

    // MARK: Thumbnails

    /// Requests a thumbnail sized for a grid cell. The handler may fire twice
    /// (degraded then final) because of `.opportunistic` delivery.
    /// Pass `allowNetwork: false` for grid cells so scrolling never triggers
    /// iCloud downloads — the locally cached derivative is always available.
    func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        allowNetwork: Bool = true,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        // Opportunistic still paints a cheap preview first; `.exact` requires
        // the final callback to match the physical cell size instead of
        // allowing PhotoKit to stop at a visibly softer nearby rendition.
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = allowNetwork
        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, _ in
            // Opportunistic PhotoKit callbacks may fire before requestImage
            // returns. Always defer state delivery so callers can first store
            // the returned request ID and cancellation remains correct.
            Task { @MainActor in completion(image) }
        }
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
        completion: @escaping (UIImage?) -> Void
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
        _ image: UIImage,
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
        completion: @escaping (UIImage?, Bool) -> Void
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
            if let image, !degraded, hasDisplayPixels, let cacheKey {
                let pixelWidth = Int(image.size.width * image.scale)
                let pixelHeight = Int(image.size.height * image.scale)
                self.detailImageCache.setObject(
                    image,
                    forKey: cacheKey,
                    cost: pixelWidth * pixelHeight * 4
                )
            }
            Task { @MainActor in completion(image, degraded) }
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
        completion: @escaping (UIImage?) -> Void
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
            if let image, !degraded, let cacheKey {
                let pixelWidth = Int(image.size.width * image.scale)
                let pixelHeight = Int(image.size.height * image.scale)
                self.detailImageCache.setObject(
                    image,
                    forKey: cacheKey,
                    cost: pixelWidth * pixelHeight * 4
                )
            }
            Task { @MainActor in completion(image) }
        }
    }

    /// Reads the actual current-version image bytes only when they already
    /// exist on this device, then downsamples with ImageIO to the display
    /// target. Unlike `requestImage`, this path cannot confuse a locally cached
    /// grid rendition with the local original. Network stays disabled.
    func requestLocalOriginalScreenImage(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
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

    /// Matches `requestThumbnail`'s sizing options (minus `.opportunistic`,
    /// which is invalid for caching): exact resize, local-only.
    private static var cachingOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
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
        guard targetSize.width.isFinite, targetSize.height.isFinite,
              targetSize.width < 100_000, targetSize.height < 100_000
        else { return nil }
        let width = Int(targetSize.width.rounded(.up))
        let height = Int(targetSize.height.rounded(.up))
        let mode = contentMode == .aspectFill ? "fill" : "fit"
        return "\(asset.localIdentifier)|\(width)x\(height)|\(mode)|\(tier.rawValue)" as NSString
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
    ) -> UIImage? {
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
        return UIImage(cgImage: cgImage)
    }

    private nonisolated static func hasDisplayResolution(
        _ image: UIImage,
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
    }

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

    // MARK: Change observation

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
    }
}

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.pendingStructuralChange =
                self.pendingStructuralChange || self.isStructural(changeInstance)
            // Both tokens share one trailing-edge debounce: iCloud downloads
            // during an index run fire a change per asset, and a full-library
            // reload per photo is what made the grid flicker and the device
            // heat up. Consumers see ≤1 bump/s.
            guard self.pendingChangeTokenBump == nil else { return }
            self.pendingChangeTokenBump = Task { @MainActor in
                defer {
                    self.pendingChangeTokenBump = nil
                    self.pendingStructuralChange = false
                }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.libraryChangeToken += 1
                // PhotoKit also reports content-only changes when an
                // iCloud/local rendition is downloaded or cached, or a
                // favorite is toggled. Those must not reload the grid or
                // launch a fresh index pass after closing Detail.
                if self.pendingStructuralChange {
                    self.assetChangeToken += 1
                }
            }
        }
    }

    /// Whether a change altered browsable asset membership or order, as opposed
    /// to only the contents of assets that were already there. Also advances
    /// the `allPhotosFetchResult` baseline.
    private func isStructural(_ changeInstance: PHChange) -> Bool {
        // No baseline (authorization not yet granted when observation started):
        // can't classify, so assume the list moved.
        guard let current = allPhotosFetchResult else { return true }
        // Nil details = this change didn't touch the all-photos fetch result.
        guard let details = changeInstance.changeDetails(for: current) else { return false }
        allPhotosFetchResult = details.fetchResultAfterChanges
        // PhotoKit couldn't compute a diff — treat as "reload everything".
        guard details.hasIncrementalChanges else { return true }
        return details.insertedIndexes?.isEmpty == false
            || details.removedIndexes?.isEmpty == false
            || details.hasMoves
    }
}
