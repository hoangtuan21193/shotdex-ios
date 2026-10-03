import Foundation
import Photos

/// Reads Photos' own caption and keywords (iOS 27, `PHAsset.extendedMetadata`)
/// for a set of assets — Info's live read, the bulk sheet's starting state,
/// and every page of the mirror's full read (FS-02.07 §8). The PhotoKit
/// version fetches with `prefetchAssetExtendedMetadata`, so a page of 1,000
/// is one fetch, never 1,000 lazy loads; tests use a fake that counts both.
protocol ExtendedMetadataReading: Sendable {
    /// The caption and keywords of every id that still exists; a deleted or
    /// unshared id is absent.
    func read(ids: [String]) -> [String: CaptionKeywords]
}

@available(iOS 27, *)
struct PhotoKitExtendedMetadataReader: ExtendedMetadataReading {
    func read(ids: [String]) -> [String: CaptionKeywords] {
        guard !ids.isEmpty else { return [:] }
        return autoreleasepool {
            let options = PHFetchOptions()
            options.prefetchAssetExtendedMetadata = true
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
            var result: [String: CaptionKeywords] = [:]
            result.reserveCapacity(fetch.count)
            fetch.enumerateObjects { asset, _, _ in
                let metadata = asset.extendedMetadata
                result[asset.localIdentifier] = CaptionKeywords(caption: metadata.caption, keywords: metadata.keywords)
            }
            return result
        }
    }
}
