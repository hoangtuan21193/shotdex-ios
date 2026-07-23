import Foundation
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

/// Wraps PhotoKit: authorization, asset fetching, thumbnails, favorites,
/// and library change observation. Nothing above this layer touches Photos.
@MainActor
@Observable
final class PhotoLibraryService: NSObject {
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "photoauth")

    private(set) var authorizationState: PhotoAuthorizationState
    /// Bumped on every library change so views can re-fetch.
    private(set) var libraryChangeToken = 0

    @ObservationIgnored
    private let imageManager = PHCachingImageManager()
    @ObservationIgnored
    private var isObservingChanges = false
    /// Trailing-edge debounce for `libraryChangeToken`: iCloud downloads
    /// during an index run fire `photoLibraryDidChange` per asset; bumping
    /// the token each time would trigger a full-library reload per photo.
    @ObservationIgnored
    private var pendingChangeTokenBump: Task<Void, Never>?
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
        allowNetwork: Bool = true,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowNetwork
        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    func cancelThumbnailRequest(_ requestId: PHImageRequestID) {
        imageManager.cancelImageRequest(requestId)
    }

    /// Full-screen image for the detail viewer. `.opportunistic` delivers a
    /// degraded preview first, then the full asset; `progress` reports the
    /// iCloud download 0…1 (only fires for assets that must stream). The
    /// completion Bool is `PHImageResultIsDegradedKey` — `false` means the
    /// final full-resolution image arrived, so callers can drop the
    /// downloading indicator.
    func requestDetailImage(
        for asset: PHAsset,
        targetSize: CGSize,
        allowNetwork: Bool = true,
        progress: @escaping (Double) -> Void,
        completion: @escaping (UIImage?, Bool) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
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
            completion(image, degraded)
        }
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
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            completion(image)
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

    /// Matches `requestThumbnail`'s options (minus `.opportunistic`, which is
    /// invalid for caching): fast resize, local-only.
    private static var cachingOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        return options
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

    // MARK: Change observation

    private func startObservingChanges() {
        guard !isObservingChanges else { return }
        PHPhotoLibrary.shared().register(self)
        isObservingChanges = true
    }
}

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            if let current = self.allPhotosFetchResult,
               let details = changeInstance.changeDetails(for: current) {
                self.allPhotosFetchResult = details.fetchResultAfterChanges
            }
            // The fetch result above stays current on every change; only the
            // token consumers (full-screen reloads) are debounced to ≤1/s.
            guard self.pendingChangeTokenBump == nil else { return }
            self.pendingChangeTokenBump = Task { @MainActor in
                defer { self.pendingChangeTokenBump = nil }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.libraryChangeToken += 1
            }
        }
    }
}
