import CoreGraphics
import Foundation
import Observation

/// One folder of the server browser (FS-17.01 §2–§4): its listing, order,
/// thumbnails for the tiles on screen, In Library marks and the selection.
@MainActor
@Observable
final class ServerFolderModel {
    enum Listing: Equatable {
        case loading
        case loaded
        case failed(RemoteFileError)
    }

    let session: ServerBrowseSession
    let folder: String
    private(set) var listing: Listing = .loading
    private(set) var contents = ServerFolderContents.empty
    /// `contents.photos` in the chosen order.
    private(set) var photos: [ServerPhoto] = []
    private(set) var sort: ServerPhotoSort
    private(set) var ascending: Bool
    /// Date Taken is reading every file's date; the grid keeps its order
    /// until this is done, then sorts once.
    private(set) var dateProgress: (done: Int, total: Int)?
    private(set) var thumbnails: [String: CGImage] = [:]
    /// Tiles known to have no preview — the format icon.
    private(set) var withoutPreview: Set<String> = []
    private(set) var inLibrary: Set<String> = []
    private(set) var known: [KnownRemoteFile] = []
    var isSelecting = false {
        didSet { if !isSelecting { selected = [] } }
    }
    private(set) var selected: Set<String> = []

    private let cache: RemoteThumbnailCache
    private let downloads: ServerDownloadStore
    private let existingAssetIds: @Sendable ([String]) -> Set<String>
    private let defaults: UserDefaults
    private var captureDates: [String: Date] = [:]
    private var thumbnailTasks: [String: Task<Void, Never>] = [:]
    private var dateTask: Task<Void, Never>?

    init(
        session: ServerBrowseSession,
        folder: String,
        cache: RemoteThumbnailCache,
        downloads: ServerDownloadStore,
        existingAssetIds: @escaping @Sendable ([String]) -> Set<String>,
        defaults: UserDefaults = .standard
    ) {
        self.session = session
        self.folder = folder
        self.cache = cache
        self.downloads = downloads
        self.existingAssetIds = existingAssetIds
        self.defaults = defaults
        let serverId = session.server.id
        sort = defaults.string(forKey: Self.sortKey(serverId)).flatMap(ServerPhotoSort.init(rawValue:)) ?? .name
        ascending = defaults.object(forKey: Self.ascendingKey(serverId)) as? Bool ?? true
    }

    private static func sortKey(_ serverId: String) -> String { "serverBrowser.sort.\(serverId)" }
    private static func ascendingKey(_ serverId: String) -> String { "serverBrowser.ascending.\(serverId)" }

    // MARK: Listing

    func load(force: Bool = false) async {
        if listing == .loaded, !force { return }
        listing = .loading
        let folder = folder
        do {
            let entries = try await session.perform { client in try await client.entries(in: folder) }
            contents = ServerFolderListing.contents(of: entries)
            listing = .loaded
            loadCachedDates()
            applyOrder()
            await refreshInLibrary()
            if sort == .dateTaken { readDates() }
        } catch {
            listing = .failed((error as? RemoteFileError) ?? .other(error.localizedDescription))
        }
    }

    /// Recomputes In Library from both histories and what the library holds.
    func refreshInLibrary() async {
        let serverId = session.server.id
        let folder = folder
        let photos = contents.photos
        let downloads = downloads
        let existing = existingAssetIds
        let (known, marked) = await Task.detached(priority: .utility) { () -> ([KnownRemoteFile], Set<String>) in
            let paths = photos.flatMap { $0.files.map { ServerUploadPath.join(folder, $0.name) } }
            let known = (try? downloads.knownFiles(serverId: serverId, paths: paths)) ?? []
            let present = existing(Array(Set(known.map(\.assetId))))
            return (known, ServerImportIndex.inLibrary(photos: photos, folder: folder, known: known, existingAssetIds: present))
        }.value
        self.known = known
        inLibrary = marked
    }

    /// A download just saved these.
    func markInLibrary(_ ids: Set<String>) {
        inLibrary.formUnion(ids)
        Task { await refreshInLibrary() }
    }

    // MARK: Sort

    func setSort(_ newSort: ServerPhotoSort) {
        guard newSort != sort else { return }
        sort = newSort
        defaults.set(newSort.rawValue, forKey: Self.sortKey(session.server.id))
        dateTask?.cancel()
        dateProgress = nil
        if newSort == .dateTaken {
            readDates()
        } else {
            applyOrder()
        }
    }

    func setAscending(_ value: Bool) {
        ascending = value
        defaults.set(value, forKey: Self.ascendingKey(session.server.id))
        if dateProgress == nil { applyOrder() }
    }

    private func applyOrder() {
        photos = sort.sorted(contents.photos, ascending: ascending, captureDates: captureDates)
    }

    private func cacheKey(_ photo: ServerPhoto) -> RemoteThumbnailCache.Key {
        .init(connectionId: session.server.id, path: ServerUploadPath.join(folder, photo.primary.name),
              size: photo.primary.size, modified: photo.primary.modified)
    }

    private func loadCachedDates() {
        for photo in contents.photos {
            if let entry = cache.entry(for: cacheKey(photo)), entry.hasCaptureDate, let date = entry.captureDate {
                captureDates[photo.id] = date
            }
        }
    }

    /// Date Taken: every photo's date, read in turn, then one sort
    /// (FS-17.01 §2).
    private func readDates() {
        let missing = contents.photos.filter { photo in
            captureDates[photo.id] == nil && !(cache.entry(for: cacheKey(photo))?.hasCaptureDate ?? false)
        }
        guard !missing.isEmpty else {
            applyOrder()
            return
        }
        dateProgress = (0, missing.count)
        let folder = folder
        let session = session
        let cache = cache
        dateTask = Task { [weak self] in
            for (index, photo) in missing.enumerated() {
                if Task.isCancelled { return }
                let key = await MainActor.run { self?.cacheKey(photo) }
                let date = try? await session.perform { client in
                    try await RemoteThumbnailer(client: client).captureDate(
                        of: photo.primary, at: ServerUploadPath.join(folder, photo.primary.name)
                    )
                }
                if let key { cache.storeCaptureDate(date ?? nil, for: key) }
                await MainActor.run {
                    if let date = date ?? nil { self?.captureDates[photo.id] = date }
                    self?.dateProgress = (index + 1, missing.count)
                }
            }
            await MainActor.run {
                self?.dateProgress = nil
                self?.applyOrder()
            }
        }
    }

    // MARK: Thumbnails

    /// A tile came on screen: from the cache, else from the server.
    func requestThumbnail(for photo: ServerPhoto) {
        let id = photo.id
        guard thumbnails[id] == nil, !withoutPreview.contains(id), thumbnailTasks[id] == nil else { return }
        let key = cacheKey(photo)
        let cache = cache
        let session = session
        let folder = folder
        thumbnailTasks[id] = Task { [weak self] in
            let cached = await Task.detached(priority: .userInitiated) { cache.entry(for: key) }.value
            if let cached, cached.hasThumbnailResult {
                self?.apply(image: cached.image, date: cached.captureDate, to: id)
                return
            }
            do {
                let result = try await session.perform { client in
                    try await RemoteThumbnailer(client: client).thumbnail(for: photo, in: folder)
                }
                cache.store(result, for: key)
                self?.apply(image: result.thumbnail?.image, date: result.captureDate, to: id)
            } catch {
                // Cancelled (scrolled away) or the server failed: try again
                // the next time the tile shows.
                self?.thumbnailTasks[id] = nil
            }
        }
    }

    /// A tile left the screen before its thumbnail arrived.
    func cancelThumbnail(for id: String) {
        thumbnailTasks.removeValue(forKey: id)?.cancel()
    }

    private func apply(image: CGImage?, date: Date?, to id: String) {
        thumbnailTasks[id] = nil
        if let image {
            thumbnails[id] = image
        } else {
            withoutPreview.insert(id)
        }
        if let date, captureDates[id] == nil { captureDates[id] = date }
    }

    func close() {
        thumbnailTasks.values.forEach { $0.cancel() }
        thumbnailTasks = [:]
        dateTask?.cancel()
    }

    // MARK: Selection

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func selectAll() {
        selected = Set(photos.map(\.id))
    }

    var selectedPhotos: [ServerPhoto] {
        photos.filter { selected.contains($0.id) }
    }
}
