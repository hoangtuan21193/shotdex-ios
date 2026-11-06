import Foundation
import Observation
import Photos

/// The PhotoKit side of Keep in Photos, behind a protocol so the sync can be
/// tested without a photo library.
protocol PhotosAlbumWriting: Sendable {
    func albumExists(_ id: String) async -> Bool
    func title(of id: String) async -> String?
    func assetIds(in id: String) async -> [String]
    func createAlbum(named name: String) async throws -> String
    func rename(_ id: String, to name: String) async throws
    func add(_ assetIds: [String], to id: String) async throws
    func remove(_ assetIds: [String], from id: String) async throws
}

/// Keeps each smart album with Keep in Photos on equal to one real album in
/// Photos (FS-06.12): added, taken out, renamed — never a photo deleted, and
/// never an album ShotDex did not make. Exists because PhotoKit cannot move
/// photos to the iCloud Shared Library; the person does that in Photos, from
/// this album.
@MainActor @Observable
final class PhotosAlbumSync {
    /// Items written so far in the running pass, per smart album — the
    /// `Updating album in Photos… 3,200 of 8,412` line.
    private(set) var progress: [String: (done: Int, total: Int)] = [:]
    /// Bumps after every pass, so screens re-read the links.
    private(set) var generation = 0

    private let albums: SmartAlbumStore
    private let links: SmartAlbumPhotosAlbumStore
    private let writer: PhotosAlbumWriting
    private let canWrite: @MainActor () -> Bool
    private let now: @Sendable () -> Date
    /// At most one pass every this many seconds (FS-06.12 §4).
    let minimumGap: Duration

    private var running: Task<Void, Never>?
    private var isPending = false
    private var lastStart: ContinuousClock.Instant?

    init(database: AppDatabase, writer: PhotosAlbumWriting, canWrite: @escaping @MainActor () -> Bool,
         minimumGap: Duration = .seconds(10), now: @escaping @Sendable () -> Date = { Date() }) {
        albums = SmartAlbumStore(database: database)
        links = SmartAlbumPhotosAlbumStore(database: database)
        self.writer = writer
        self.canWrite = canWrite
        self.minimumGap = minimumGap
        self.now = now
    }

    /// Asks for a pass soon: the set may have changed (a save, an On Server
    /// batch, a library change). Calls during a pass fold into one more pass.
    func setNeedsSync() {
        guard running == nil else { isPending = true; return }
        running = Task { [weak self] in
            await self?.runCoalesced()
        }
    }

    /// One pass now, for the background task and tests.
    func syncNow() async {
        if let running { isPending = true; await running.value; return }
        let task = Task { await self.runCoalesced() }
        running = task
        await task.value
    }

    private func runCoalesced() async {
        repeat {
            isPending = false
            if let lastStart {
                let wait = minimumGap - (ContinuousClock.now - lastStart)
                if wait > .zero { try? await Task.sleep(for: wait) }
            }
            lastStart = .now
            await pass()
        } while isPending && !Task.isCancelled
        running = nil
    }

    /// Every enabled link, one after another.
    func pass() async {
        guard canWrite() else { return }
        let links = self.links
        let albums = self.albums
        let enabled = ((try? await Task.detached { try links.links() }.value) ?? []).filter(\.isEnabled)
        guard !enabled.isEmpty else { return }
        let all = (try? await Task.detached { try albums.fetchAllOrdered() }.value) ?? []
        for link in enabled {
            guard let album = all.first(where: { $0.id == link.smartAlbumId }) else { continue }
            await sync(album, link: link)
            if Task.isCancelled { break }
        }
        generation &+= 1
    }

    private func sync(_ album: SmartAlbum, link: SmartAlbumPhotosAlbum) async {
        var link = link
        let links = self.links
        let save: (SmartAlbumPhotosAlbum) async -> Void = { value in
            _ = try? await Task.detached { try links.save(value) }.value
        }
        do {
            // The album: reuse ShotDex's own, make one when there is none or
            // the switch was just turned on and it is gone; deleted in Photos
            // while kept → stop keeping it (§4).
            var albumId = link.collectionLocalId
            if let id = albumId, !(await writer.albumExists(id)) {
                if link.lastSyncedAt != nil {
                    link.isEnabled = false
                    link.state = .deletedInPhotos
                    await save(link)
                    return
                }
                albumId = nil
            }
            let id: String
            if let albumId {
                id = albumId
                if await writer.title(of: id) != album.name {
                    try await writer.rename(id, to: album.name)
                }
            } else {
                id = try await writer.createAlbum(named: album.name)
                link.collectionLocalId = id
                await save(link)
            }

            let query = album.query
            let target = try await Task.detached { try links.photoKitIds(matching: query) }.value
            let current = await writer.assetIds(in: id)
            let diff = PhotosAlbumDiff(target: target, current: current)
            if !diff.isEmpty {
                link.state = .updating
                await save(link)
                generation &+= 1
                let total = diff.add.count + diff.remove.count
                var done = 0
                progress[album.id] = (0, total)
                for batch in PhotosAlbumDiff.batches(diff.remove) {
                    try await writer.remove(batch, from: id)
                    done += batch.count
                    progress[album.id] = (done, total)
                }
                for batch in PhotosAlbumDiff.batches(diff.add) {
                    try await writer.add(batch, to: id)
                    done += batch.count
                    progress[album.id] = (done, total)
                }
            }
            progress[album.id] = nil
            link.state = .synced
            link.assetCount = target.count
            link.lastSyncedAt = Int(now().timeIntervalSince1970)
            await save(link)
        } catch {
            // Try again next pass; nothing half-done is lost, because the next
            // pass compares with what the album really holds (§4).
            progress[album.id] = nil
            link.state = .failed
            await save(link)
        }
    }
}

/// `PhotosAlbumWriting` on the real photo library.
struct LivePhotosAlbumWriter: PhotosAlbumWriting {
    private func collection(_ id: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    func albumExists(_ id: String) async -> Bool { collection(id) != nil }

    func title(of id: String) async -> String? { collection(id)?.localizedTitle }

    func assetIds(in id: String) async -> [String] {
        guard let collection = collection(id) else { return [] }
        var ids: [String] = []
        PHAsset.fetchAssets(in: collection, options: nil).enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
    }

    func createAlbum(named name: String) async throws -> String {
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            placeholder = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                .placeholderForCreatedAssetCollection
        }
        guard let id = placeholder?.localIdentifier else { throw PhotoImportError.creationFailed }
        return id
    }

    func rename(_ id: String, to name: String) async throws {
        guard let collection = collection(id) else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: collection)?.title = name
        }
    }

    func add(_ assetIds: [String], to id: String) async throws {
        try await change(id, assetIds) { $0.addAssets($1) }
    }

    func remove(_ assetIds: [String], from id: String) async throws {
        try await change(id, assetIds) { $0.removeAssets($1) }
    }

    private func change(_ id: String, _ assetIds: [String],
                        _ apply: @escaping @Sendable (PHAssetCollectionChangeRequest, PHFetchResult<PHAsset>) -> Void) async throws {
        guard let collection = collection(id) else { throw PhotoImportError.creationFailed }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        guard assets.count > 0 else { return }
        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            apply(request, assets)
        }
    }
}
