import Foundation
import CoreLocation
import Photos

/// Library mutations beyond the favorite/delete pair the app started with:
/// hiding, capture-date and location correction, album membership and album
/// lifecycle. Every one of these goes through `PHPhotoLibrary.performChanges`,
/// so PhotoKit — not the local database — stays the source of truth; callers
/// let the normal `photoLibraryDidChange` path refresh the index.
extension PhotoLibraryService {

    // MARK: Favorite (batch)

    /// Batch counterpart of `setFavorite(_:for:)`. One `performChanges` block for
    /// the whole selection, so the user sees a single undo entry in Photos and
    /// PhotoKit fires one change notification instead of N.
    func setFavorite(_ isFavorite: Bool, for assets: [PHAsset]) async throws {
        let targets = assets.filter { $0.isFavorite != isFavorite }
        guard !targets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            for asset in targets {
                PHAssetChangeRequest(for: asset).isFavorite = isFavorite
            }
        }
    }

    // MARK: Hidden

    /// Moves assets into (or out of) the system Hidden album.
    ///
    /// Hiding is a per-asset flag, not a collection membership, so an asset can
    /// be hidden while still belonging to user albums — exactly how Photos
    /// behaves. Whether the Hidden album is itself browsable is a Settings
    /// switch the user owns; we never try to override it.
    func setHidden(_ isHidden: Bool, for assets: [PHAsset]) async throws {
        let targets = assets.filter { $0.isHidden != isHidden }
        guard !targets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            for asset in targets {
                PHAssetChangeRequest(for: asset).isHidden = isHidden
            }
        }
    }

    /// The system "Hidden" smart album, or `nil` when the device has none
    /// (it is absent until the first asset is hidden).
    nonisolated static func fetchHiddenAlbum() -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumAllHidden,
            options: nil
        ).firstObject
    }

    // MARK: Capture date

    /// Rewrites the capture date of each asset.
    ///
    /// PhotoKit writes this straight onto the asset, so it propagates to iCloud
    /// and to every other Photos client. It does **not** rewrite the EXIF inside
    /// the original file — Photos behaves the same way — so the indexed EXIF row
    /// keeps the camera's value while sort and grouping follow the new date.
    func setCreationDate(_ date: Date, for assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            for asset in assets {
                PHAssetChangeRequest(for: asset).creationDate = date
            }
        }
    }

    /// Shifts every asset's capture date by a fixed interval, preserving the
    /// spacing between them. This is what "adjust date & time" on a multi-photo
    /// selection means in Photos: the user picks a new date for the *first*
    /// photo and the rest move with it.
    func shiftCreationDates(by interval: TimeInterval, for assets: [PHAsset]) async throws {
        let targets = assets.filter { $0.creationDate != nil }
        guard !targets.isEmpty, interval != 0 else { return }
        try await PHPhotoLibrary.shared().performChanges {
            for asset in targets {
                guard let current = asset.creationDate else { continue }
                PHAssetChangeRequest(for: asset).creationDate =
                    current.addingTimeInterval(interval)
            }
        }
    }

    // MARK: Location

    /// Sets, or with a `nil` location clears, the GPS coordinate of each asset.
    func setLocation(_ location: CLLocation?, for assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            for asset in assets {
                PHAssetChangeRequest(for: asset).location = location
            }
        }
    }

    // MARK: Album membership

    /// Removes assets from one user album without deleting them from the
    /// library. Smart albums and shared albums reject this, hence the
    /// `canPerform` guard rather than a silent no-op inside the change block.
    func removeAssets(_ assets: [PHAsset], from collection: PHAssetCollection) async throws {
        guard !assets.isEmpty,
              collection.canPerform(.removeContent)
        else { return }
        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            request.removeAssets(assets as NSArray)
        }
    }

    /// Moves assets inside a user album's manual order. `indexes` are positions
    /// in the album's own (unsorted) fetch order; `destination` is the index the
    /// block lands before.
    func moveAssets(
        at indexes: IndexSet,
        to destination: Int,
        in collection: PHAssetCollection
    ) async throws {
        guard !indexes.isEmpty,
              collection.canPerform(.rearrangeContent)
        else { return }
        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            request.moveAssets(at: indexes, to: max(0, destination))
        }
    }

    // MARK: Album lifecycle

    /// Renames a user album. Smart albums reject the change.
    func renameAlbum(_ collection: PHAssetCollection, to title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              collection.canPerform(.rename)
        else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: collection)?.title = trimmed
        }
    }

    /// Deletes user albums. The photos inside stay in the library — Photos does
    /// the same, and it is the difference between "Delete Album" and "Delete
    /// Photos" that users rely on.
    func deleteAlbums(_ collections: [PHAssetCollection]) async throws {
        let targets = collections.filter { $0.canPerform(.delete) }
        guard !targets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.deleteAssetCollections(targets as NSArray)
        }
    }

    // MARK: Folders

    /// Every user folder (a `PHCollectionList` of kind `.folder`).
    nonisolated static func fetchFolders() -> [PHCollectionList] {
        var folders: [PHCollectionList] = []
        PHCollectionList.fetchCollectionLists(
            with: .folder,
            subtype: .any,
            options: nil
        ).enumerateObjects { list, _, _ in folders.append(list) }
        return folders
    }

    /// Albums and sub-folders directly inside `folder`, in the folder's order.
    nonisolated static func fetchChildren(of folder: PHCollectionList) -> [PHCollection] {
        var children: [PHCollection] = []
        PHCollection.fetchCollections(in: folder, options: nil)
            .enumerateObjects { collection, _, _ in children.append(collection) }
        return children
    }

    /// Albums that sit at the top level, i.e. are not inside any folder.
    /// PhotoKit has no "parent" property on a collection, so membership is
    /// derived by subtracting every folder's children from the full album list.
    nonisolated static func fetchTopLevelUserAlbums() -> [PHAssetCollection] {
        var nested: Set<String> = []
        for folder in fetchFolders() {
            for child in fetchChildren(of: folder) {
                nested.insert(child.localIdentifier)
            }
        }
        return fetchUserAlbums().filter { !nested.contains($0.localIdentifier) }
    }

    func createFolder(named name: String) async throws -> PHCollectionList {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PhotoImportError.creationFailed }
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHCollectionListChangeRequest
                .creationRequestForCollectionList(withTitle: trimmed)
            placeholder = request.placeholderForCreatedCollectionList
        }
        guard let id = placeholder?.localIdentifier,
              let list = PHCollectionList.fetchCollectionLists(
                  withLocalIdentifiers: [id], options: nil
              ).firstObject
        else { throw PhotoImportError.creationFailed }
        return list
    }

    func renameFolder(_ folder: PHCollectionList, to title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, folder.canPerform(.rename) else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHCollectionListChangeRequest(for: folder)?.title = trimmed
        }
    }

    /// Deletes folders. Albums inside a deleted folder return to the top level
    /// rather than being destroyed.
    func deleteFolders(_ folders: [PHCollectionList]) async throws {
        let targets = folders.filter { $0.canPerform(.delete) }
        guard !targets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHCollectionListChangeRequest.deleteCollectionLists(targets as NSArray)
        }
    }

    func moveCollections(_ collections: [PHCollection], into folder: PHCollectionList) async throws {
        guard !collections.isEmpty, folder.canPerform(.addContent) else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHCollectionListChangeRequest(for: folder)?
                .addChildCollections(collections as NSArray)
        }
    }

    func removeCollections(_ collections: [PHCollection], from folder: PHCollectionList) async throws {
        guard !collections.isEmpty, folder.canPerform(.removeContent) else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHCollectionListChangeRequest(for: folder)?
                .removeChildCollections(collections as NSArray)
        }
    }
}
