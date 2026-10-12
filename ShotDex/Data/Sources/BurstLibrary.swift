import Foundation
import Photos

/// Where the Bursts tab and the frame picker read bursts from (FS-02.05,
/// FS-06.06 §7b). Straight from PhotoKit — no fingerprints, no scan.
@MainActor
protocol BurstLibrary: AnyObject {
    /// Every burst the app can see, newest first, without frame counts.
    func bursts() async -> [BurstSummary]
    /// The frames of one burst in capture order, with Photos' suggestion and
    /// pick flags. Under `.limited` only the frames the user shared.
    func frames(ofBurst id: String) async -> [BurstFrame]
    /// The burst a photo belongs to, if any.
    func burstId(of assetId: String) -> String?
    /// The asset behind a frame, for its image.
    func asset(for frameId: String) -> PHAsset?
}

/// The app's burst source: the Bursts smart album for the list, a burst
/// fetch with `includeAllBurstAssets` for the frames.
@MainActor
final class PhotoKitBurstLibrary: BurstLibrary {
    private var assetsById: [String: PHAsset] = [:]

    func bursts() async -> [BurstSummary] {
        await Task.detached(priority: .userInitiated) {
            let albums = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: .smartAlbumBursts, options: nil
            )
            guard let album = albums.firstObject else { return [BurstSummary]() }
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let covers = PHAsset.fetchAssets(in: album, options: options)
            var rows: [BurstSummary] = []
            rows.reserveCapacity(covers.count)
            covers.enumerateObjects { asset, _, _ in
                guard let id = asset.burstIdentifier else { return }
                rows.append(BurstSummary(id: id, coverId: asset.localIdentifier, date: asset.creationDate))
            }
            return rows
        }.value
    }

    func frames(ofBurst id: String) async -> [BurstFrame] {
        let assets = await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.includeAllBurstAssets = true
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let result = PHAsset.fetchAssets(withBurstIdentifier: id, options: options)
            var members: [PHAsset] = []
            result.enumerateObjects { member, _, _ in members.append(member) }
            return members
        }.value
        for asset in assets { assetsById[asset.localIdentifier] = asset }
        return assets.map {
            BurstFrame(
                id: $0.localIdentifier,
                isSuggested: $0.burstSelectionTypes.contains(.autoPick),
                isPickedInPhotos: $0.burstSelectionTypes.contains(.userPick)
            )
        }
    }

    func burstId(of assetId: String) -> String? {
        asset(for: assetId)?.burstIdentifier
    }

    func asset(for frameId: String) -> PHAsset? {
        if let cached = assetsById[frameId] { return cached }
        let asset = PhotoLibraryService.fetchAssets(ids: [frameId]).first
        assetsById[frameId] = asset
        return asset
    }
}

#if DEBUG
/// Bursts made of ordinary library photos, for the simulator — which cannot
/// hold a real burst (PHOTOS_PARITY B8). `-ShotDexFakeBursts` turns it on.
/// Runs of photos shot within two minutes of each other become a burst; the
/// second frame of each run is "suggested", every third run has none.
@MainActor
final class FakeBurstLibrary: BurstLibrary {
    static let launchArgument = "-ShotDexFakeBursts"
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    private var runs: [String: [PHAsset]] = [:]
    private var order: [String] = []

    private func load() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var all: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in all.append(asset) }
        runs = [:]
        order = []
        var current: [PHAsset] = []
        func close() {
            guard current.count >= 2 else { current = []; return }
            let id = "fake-burst-\(current[0].localIdentifier)"
            runs[id] = current
            order.append(id)
            current = []
        }
        for asset in all {
            if let last = current.last, let a = last.creationDate, let b = asset.creationDate, b.timeIntervalSince(a) > 120 {
                close()
            }
            current.append(asset)
        }
        close()
    }

    func bursts() async -> [BurstSummary] {
        load()
        return BurstSummary.sorted(order.compactMap { id in
            guard let first = runs[id]?.first else { return nil }
            return BurstSummary(id: id, coverId: first.localIdentifier, date: first.creationDate)
        })
    }

    func frames(ofBurst id: String) async -> [BurstFrame] {
        load()
        guard let run = runs[id] else { return [] }
        let hasSuggestion = (order.firstIndex(of: id) ?? 0) % 3 != 2
        return run.enumerated().map { index, asset in
            BurstFrame(id: asset.localIdentifier, isSuggested: hasSuggestion && index == 1, isPickedInPhotos: false)
        }
    }

    func burstId(of assetId: String) -> String? {
        if runs.isEmpty { load() }
        return runs.first { $0.value.contains { $0.localIdentifier == assetId } }?.key
    }

    func asset(for frameId: String) -> PHAsset? {
        if runs.isEmpty { load() }
        for run in runs.values {
            if let asset = run.first(where: { $0.localIdentifier == frameId }) { return asset }
        }
        return PhotoLibraryService.fetchAssets(ids: [frameId]).first
    }
}
#endif

extension PhotoKitBurstLibrary {
    /// The burst source the app uses: the real one, or in a DEBUG build run
    /// with `-ShotDexFakeBursts`, bursts made of ordinary photos.
    static func makeForApp() -> any BurstLibrary {
        #if DEBUG
        if FakeBurstLibrary.isEnabled { return FakeBurstLibrary() }
        #endif
        return PhotoKitBurstLibrary()
    }
}
