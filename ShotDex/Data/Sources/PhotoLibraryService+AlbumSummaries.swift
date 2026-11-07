import Foundation
import Photos

/// One of Photos' own albums as a Collections tile reads it: its name, how
/// many photos and videos it holds, and the newest one for its cover.
struct AlbumSummary: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let count: Int
    let coverAssetId: String?
}

extension PhotoLibraryService {
    /// The user's albums with their counts and covers, in Photos' own order
    /// (the order the user arranged them in). Empty albums are left out, as
    /// Collections shows them. Off the main actor: one fetch per album.
    /// `includesEmpty`: the Mac's Albums lists an album just made with +.
    nonisolated static func fetchUserAlbumSummaries(includesEmpty: Bool = false) -> [AlbumSummary] {
        // The count from an unsorted fetch; the cover from a sorted one that
        // stops at the first photo.
        let counting = PHFetchOptions()
        counting.predicate = browsableMediaPredicate
        let newest = PHFetchOptions()
        newest.predicate = browsableMediaPredicate
        newest.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        newest.fetchLimit = 1
        return fetchUserAlbums().compactMap { album in
            let count = PHAsset.fetchAssets(in: album, options: counting).count
            guard count > 0 || includesEmpty else { return nil }
            return AlbumSummary(id: album.localIdentifier, title: album.localizedTitle ?? "", count: count,
                                coverAssetId: count > 0 ? PHAsset.fetchAssets(in: album, options: newest).firstObject?.localIdentifier : nil)
        }
    }

    /// The photos of one album, in the album's order — an album opened as a
    /// place (the grid sorts them its own way).
    nonisolated static func assetIds(inAlbum albumId: String) -> [String] {
        guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil).firstObject
        else { return [] }
        let options = PHFetchOptions()
        options.predicate = browsableMediaPredicate
        var ids: [String] = []
        PHAsset.fetchAssets(in: album, options: options).enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
    }
}
