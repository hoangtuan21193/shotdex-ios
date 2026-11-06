import Foundation
import Observation
import os
import Photos

/// The PhotoKit side of Keep in Photos, behind a protocol so the sync can be
/// tested without a photo library.
protocol PhotosAlbumWriting: Sendable {
    func albumExists(_ id: String) async -> Bool
    func title(of id: String) async -> String?
    func assetIds(in id: String) async -> [String]
    /// The ids among `ids` Photos still has — gone, trashed or otherwise
    /// unreadable ones are left out so a pass can settle (FS-06.12 §4).
    func existing(_ ids: [String]) async -> Set<String>
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
    nonisolated static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "PhotosAlbumSync")

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
    private var retry: Task<Void, Never>?
    /// Set by `syncNow`: the next pass does not wait out the gap.
    private var skipsGap = false

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
            await self?.runCoalesced(waitsForGap: true)
        }
    }

    /// One pass now, without waiting out the gap — for the background slot,
    /// where seconds count, and for tests. Cancelling the caller cancels it.
    func syncNow() async {
        skipsGap = true
        if let running {
            isPending = true
            await withTaskCancellationHandler { await running.value } onCancel: { running.cancel() }
            return
        }
        let task = Task { await self.runCoalesced(waitsForGap: true) }
        running = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func runCoalesced(waitsForGap: Bool) async {
        var waits = waitsForGap
        repeat {
            if waits, !skipsGap, let lastStart {
                let wait = minimumGap - (ContinuousClock.now - lastStart)
                if wait > .zero { try? await Task.sleep(for: wait) }
            }
            waits = true
            skipsGap = false
            guard !Task.isCancelled else { break }
            // Cleared only now: a request that came in during the wait is
            // answered by this pass, not by one more after it.
            isPending = false
            lastStart = .now
            await pass()
        } while isPending && !Task.isCancelled
        running = nil
    }

    /// A link was turned on or off outside a pass: screens re-read it.
    func linksChanged() { generation &+= 1 }

    /// Every enabled link, one after another.
    func pass() async {
        let links = self.links
        let albums = self.albums
        let enabled: [SmartAlbumPhotosAlbum]
        do {
            enabled = try await Task.detached { try links.links() }.value.filter(\.isEnabled)
        } catch {
            Self.logger.error("links: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !enabled.isEmpty else { generation &+= 1; return }
        // Without Full Access the album cannot be "exactly these photos":
        // say so on every kept album rather than sit on an old answer.
        guard canWrite() else {
            for var link in enabled where link.state != .needsFullAccess {
                link.state = .needsFullAccess
                await save(link)
            }
            generation &+= 1
            return
        }
        let all: [SmartAlbum]
        do {
            all = try await Task.detached { try albums.fetchAllOrdered() }.value
        } catch {
            Self.logger.error("smart albums: \(error.localizedDescription, privacy: .public)")
            return
        }
        for link in enabled {
            guard !Task.isCancelled else { break }
            guard let album = all.first(where: { $0.id == link.smartAlbumId }) else { continue }
            await sync(album, link: link)
        }
        generation &+= 1
    }

    /// Writes the pass's own columns back; false when the link went off or
    /// away meanwhile — the pass then stops touching the album.
    @discardableResult
    private func save(_ link: SmartAlbumPhotosAlbum) async -> Bool {
        let links = self.links
        do {
            return try await Task.detached { try links.recordSync(link) }.value
        } catch {
            Self.logger.error("save link \(link.smartAlbumId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func sync(_ album: SmartAlbum, link: SmartAlbumPhotosAlbum) async {
        var link = link
        let links = self.links
        do {
            // The album: reuse ShotDex's own, make one when there is none or
            // the switch was just turned on and it is gone; deleted in Photos
            // while kept → stop keeping it (§4).
            var albumId = link.collectionLocalId
            if let id = albumId, !(await writer.albumExists(id)) {
                // `lastSyncedAt` is set the moment ShotDex makes the album and
                // cleared when the switch is turned on again.
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
                link.lastSyncedAt = Int(now().timeIntervalSince1970)
                // Lose this id and the next pass makes a second album.
                guard await save(link) else { throw PhotosAlbumSyncError.lostAlbumId }
            }

            let query = album.query
            let wanted = try await Task.detached { try links.photoKitIds(matching: query) }.value
            // Only what Photos can still hand over: an id it cannot resolve
            // would be "added" on every pass and the album never settle.
            let resolvable = await writer.existing(wanted)
            let target = wanted.filter(resolvable.contains)
            if target.count < wanted.count {
                Self.logger.notice("\(album.id, privacy: .public): \(wanted.count - target.count) ids Photos no longer has")
            }
            let current = await writer.assetIds(in: id)
            let diff = PhotosAlbumDiff(target: target, current: current)
            if !diff.isEmpty {
                link.state = .updating
                guard await save(link) else { throw CancellationError() }
                generation &+= 1
                let total = diff.add.count + diff.remove.count
                var done = 0
                progress[album.id] = (0, total)
                let runs = PhotosAlbumDiff.batches(diff.remove).map { (adds: false, ids: $0) }
                    + PhotosAlbumDiff.batches(diff.add).map { (adds: true, ids: $0) }
                for (adds, batch) in runs {
                    // A background slot can end mid-pass; the next pass picks
                    // up from what the album really holds.
                    try Task.checkCancellation()
                    // Turned off or deleted meanwhile: stop touching the album.
                    let smartAlbumId = album.id
                    guard (try? await Task.detached { try links.isEnabled(smartAlbumId) }.value) == true else {
                        throw CancellationError()
                    }
                    if adds {
                        try await writer.add(batch, to: id)
                    } else {
                        try await writer.remove(batch, from: id)
                    }
                    done += batch.count
                    progress[album.id] = (done, total)
                }
            }
            progress[album.id] = nil
            link.state = .synced
            link.assetCount = target.count
            link.lastSyncedAt = Int(now().timeIntervalSince1970)
            await save(link)
        } catch is CancellationError {
            progress[album.id] = nil
        } catch {
            // Try again next pass; nothing half-done is lost, because the next
            // pass compares with what the album really holds (§4).
            Self.logger.error("sync \(album.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            progress[album.id] = nil
            link.state = .failed
            await save(link)
            // An album Photos will not let ShotDex edit stays that way: no
            // retry loop every minute; the next real change tries again.
            if !(error is PhotosAlbumSyncError) { retryLater() }
        }
    }

    /// "Will try again" (FS-06.12 §3): one more pass a minute after a
    /// failure, whatever else happens meanwhile.
    private func retryLater() {
        guard retry == nil else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.retry = nil
            self?.setNeedsSync()
        }
    }
}

enum PhotosAlbumSyncError: Error {
    /// Photos refused to change the album (not ShotDex's to edit any more).
    case albumNotEditable
    /// The album was made but its id could not be saved.
    case lostAlbumId
}

/// `PhotosAlbumWriting` on the real photo library.
struct LivePhotosAlbumWriter: PhotosAlbumWriting {
    /// Hidden photos and every frame of a burst count: a smart album can hold
    /// them, and an album member PhotoKit leaves out of a fetch would be
    /// "missing" on every pass.
    private static var everything: PHFetchOptions {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.includeAllBurstAssets = true
        return options
    }

    private func collection(_ id: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    func albumExists(_ id: String) async -> Bool { collection(id) != nil }

    func title(of id: String) async -> String? { collection(id)?.localizedTitle }

    func assetIds(in id: String) async -> [String] {
        guard let collection = collection(id) else { return [] }
        var ids: [String] = []
        PHAsset.fetchAssets(in: collection, options: Self.everything).enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }
        return ids
    }

    func existing(_ ids: [String]) async -> Set<String> {
        var found = Set<String>()
        for batch in PhotosAlbumDiff.batches(ids, size: 2_000) {
            PHAsset.fetchAssets(withLocalIdentifiers: batch, options: Self.everything).enumerateObjects { asset, _, _ in
                found.insert(asset.localIdentifier)
            }
        }
        return found
    }

    func createAlbum(named name: String) async throws -> String {
        let created = OSAllocatedUnfairLock<String?>(initialState: nil)
        try await PHPhotoLibrary.shared().performChanges {
            let id = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                .placeholderForCreatedAssetCollection.localIdentifier
            created.withLock { $0 = id }
        }
        guard let id = created.withLock({ $0 }) else { throw PhotoImportError.creationFailed }
        return id
    }

    func rename(_ id: String, to name: String) async throws {
        guard let collection = collection(id), collection.canPerform(.rename) else {
            throw PhotosAlbumSyncError.albumNotEditable
        }
        try await PHPhotoLibrary.shared().performChanges {
            // Fetched inside the block rather than captured across actors.
            guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
            else { return }
            PHAssetCollectionChangeRequest(for: collection)?.title = name
        }
        _ = collection
    }

    func add(_ assetIds: [String], to id: String) async throws {
        try await change(id, assetIds, needs: .addContent) { $0.addAssets($1) }
    }

    func remove(_ assetIds: [String], from id: String) async throws {
        try await change(id, assetIds, needs: .removeContent) { $0.removeAssets($1) }
    }

    /// Throws when Photos will not take the change, so a pass never reports
    /// synced over an album it did not write (photokit-guard review).
    private func change(_ id: String, _ assetIds: [String], needs operation: PHCollectionEditOperation,
                        _ apply: @escaping @Sendable (PHAssetCollectionChangeRequest, PHFetchResult<PHAsset>) -> Void) async throws {
        guard let collection = collection(id), collection.canPerform(operation) else {
            throw PhotosAlbumSyncError.albumNotEditable
        }
        guard PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: Self.everything).count > 0 else { return }
        let refused = OSAllocatedUnfairLock(initialState: false)
        try await PHPhotoLibrary.shared().performChanges {
            // Collection and assets fetched inside the block, not captured
            // across the actor hop (swift-concurrency review).
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: Self.everything)
            guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject,
                  let request = PHAssetCollectionChangeRequest(for: collection)
            else { refused.withLock { $0 = true }; return }
            apply(request, assets)
        }
        if refused.withLock({ $0 }) { throw PhotosAlbumSyncError.albumNotEditable }
    }
}
