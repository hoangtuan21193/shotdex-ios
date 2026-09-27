import Foundation
import Observation

/// One run of the download sheet (FS-17.02): prepare → download → result,
/// for the photos picked in the server browser.
@MainActor
@Observable
final class ServerDownloadModel {
    enum Stage: Equatable {
        case preparing
        case downloading
        case finished
    }

    /// Where the photos go.
    enum Destination: Hashable {
        case library
        case album(id: String)
    }

    struct Album: Identifiable, Hashable {
        let id: String
        let title: String
    }

    struct Progress: Equatable {
        var index = 0
        var count = 0
        var filename = ""
        var phase: ServerDownloadPhase = .downloading
        var bytesDone: Int64 = 0
        var bytesTotal: Int64 = 0
        var secondsLeft: Double?

        var fraction: Double { bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : 0 }
    }

    struct Failure: Identifiable, Equatable {
        let id: Int
        let filename: String
        let reason: String
    }

    struct Summary: Equatable {
        var savedCount = 0
        var skippedCount = 0
        var failures: [Failure] = []
        var notAttemptedCount = 0
        var stopMessage: String?
    }

    /// Everything the browser hands over for one sheet.
    struct Context {
        let server: FileServer
        let folder: String
        let photos: [ServerPhoto]
        /// Photo ids the library already has.
        let inLibrary: Set<String>
        let known: [KnownRemoteFile]
    }

    let context: Context
    private(set) var stage: Stage = .preparing
    var destination: Destination = .library
    var skipsInLibrary = true
    private(set) var albums: [Album] = []
    /// `.limited` Photos access: no albums to save into (FS-17.02 §1).
    let isLimitedAccess: Bool
    private(set) var progress = Progress()
    private(set) var summary = Summary()
    var albumError: String?

    private let makeClient: (FileServer, String) -> any RemoteFileClient
    private let password: String
    private let creator: any AssetCreating
    private let downloads: ServerDownloadStore
    private let screenHold: ScreenHolding
    private let listAlbums: () -> [Album]
    private let createAlbumNamed: (String) async throws -> String
    private let freeSpace: () -> Int64?
    /// Told which photos landed, so the grid can mark them In Library.
    private let onSaved: (Set<String>) -> Void

    private var task: Task<Void, Never>?
    private var isHolding = false
    private var lastItems: [ServerDownloadItem] = []
    private var lastOutcomes: [ServerDownloadOutcome] = []
    private var samples: [(time: Date, bytes: Int64)] = []

    init(
        context: Context,
        password: String,
        isLimitedAccess: Bool,
        makeClient: @escaping (FileServer, String) -> any RemoteFileClient,
        creator: any AssetCreating,
        downloads: ServerDownloadStore,
        screenHold: ScreenHolding,
        listAlbums: @escaping () -> [Album],
        createAlbumNamed: @escaping (String) async throws -> String,
        freeSpace: @escaping () -> Int64?,
        onSaved: @escaping (Set<String>) -> Void
    ) {
        self.context = context
        self.password = password
        self.isLimitedAccess = isLimitedAccess
        self.makeClient = makeClient
        self.creator = creator
        self.downloads = downloads
        self.screenHold = screenHold
        self.listAlbums = listAlbums
        self.createAlbumNamed = createAlbumNamed
        self.freeSpace = freeSpace
        self.onSaved = onSaved
        if !isLimitedAccess { albums = listAlbums() }
    }

    // MARK: Prepare

    var inLibraryCount: Int { context.photos.filter { context.inLibrary.contains($0.id) }.count }

    var photosToDownload: [ServerPhoto] {
        skipsInLibrary ? context.photos.filter { !context.inLibrary.contains($0.id) } : context.photos
    }

    var estimatedBytes: Int64 { photosToDownload.reduce(0) { $0 + $1.totalBytes } }

    /// Bytes short on this device, or nil when it fits with 1 GB to spare.
    var spaceShortfall: Int64? {
        guard let free = freeSpace() else { return nil }
        let needed = estimatedBytes + 1_000_000_000
        return needed > free ? needed - free : nil
    }

    var canStart: Bool { stage == .preparing && !photosToDownload.isEmpty && spaceShortfall == nil }

    /// The album this sheet made with New Album…, so that row, not
    /// Existing Album, carries the check.
    private(set) var createdAlbumId: String?

    /// The three ways in (FS-17.02 §1).
    enum Choice {
        case libraryOnly
        case existingAlbum
        case newAlbum
    }

    var choice: Choice {
        switch destination {
        case .library: .libraryOnly
        case .album(let id): id == createdAlbumId ? .newAlbum : .existingAlbum
        }
    }

    /// Photos always land in the library; an album is where else they show.
    var destinationSentence: String {
        switch destination {
        case .library:
            String(localized: "Photos are added to your library only, not to any album.", comment: "Import from server: what Library Only does")
        case .album:
            String(localized: "Photos are added to your library and to the album “\(destinationTitle)”.", comment: "Import from server: what an album destination does")
        }
    }

    var destinationTitle: String {
        switch destination {
        case .library: String(localized: "Library", comment: "Download from server: save into the library, no album")
        case .album(let id): albums.first { $0.id == id }?.title ?? String(localized: "Album", comment: "Download from server: an album whose name is unknown")
        }
    }

    func createAlbum(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let id = try await createAlbumNamed(trimmed)
            albums = listAlbums()
            if !albums.contains(where: { $0.id == id }) { albums.append(Album(id: id, title: trimmed)) }
            createdAlbumId = id
            destination = .album(id: id)
        } catch {
            albumError = error.localizedDescription
        }
    }

    // MARK: Download

    func start() {
        guard canStart else { return }
        summary = Summary()
        summary.skippedCount = context.photos.count - photosToDownload.count
        let items = photosToDownload.map { photo in
            var checksums: [String: String] = [:]
            for file in photo.files {
                let path = ServerUploadPath.join(context.folder, file.name)
                checksums[file.name] = ServerImportIndex.knownChecksum(path: path, size: file.size, known: context.known)
            }
            return ServerDownloadItem(photo: photo, folder: context.folder, knownChecksums: checksums)
        }
        run(items)
    }

    /// The photos that failed or were never reached.
    func tryAgain() {
        let remaining = zip(lastItems, lastOutcomes).compactMap { item, outcome -> ServerDownloadItem? in
            if case .saved = outcome { return nil }
            return item
        }
        guard !remaining.isEmpty else { return }
        let skipped = summary.skippedCount
        summary = Summary()
        summary.skippedCount = skipped
        run(remaining)
    }

    var hasRemaining: Bool {
        lastOutcomes.contains { if case .saved = $0 { false } else { true } }
    }

    private func run(_ items: [ServerDownloadItem]) {
        guard task == nil else { return }
        lastItems = items
        stage = .downloading
        progress = Progress(count: items.count)
        samples = []
        beginHold()

        let server = context.server
        let albumId: String? = if case .album(let id) = destination { id } else { nil }
        let downloads = downloads
        let session = ServerDownloadSession(
            client: makeClient(server, password),
            creator: creator,
            serverId: server.id,
            serverName: server.name,
            workDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(TemporaryWorkspace.serverDownloadPrefix)\(UUID().uuidString)", isDirectory: true),
            albumId: albumId,
            onEvent: { [weak self] event in
                Task { @MainActor in self?.handle(event, items: items) }
            },
            record: { try downloads.record($0) }
        )
        task = Task { [weak self] in
            let result = await session.run(items)
            self?.finish(result, items: items)
        }
    }

    func cancel() {
        task?.cancel()
    }

    func tearDown() {
        cancel()
        endHold()
    }

    private func handle(_ event: ServerDownloadEvent, items: [ServerDownloadItem]) {
        switch event {
        case .itemStarted(let index, let phase):
            progress.index = index
            progress.filename = items[index].photo.primary.name
            progress.phase = phase
        case .phase(let index, let phase):
            progress.index = index
            progress.phase = phase
        case .bytes(let done, let total):
            progress.bytesDone = max(progress.bytesDone, done)
            progress.bytesTotal = total
            let now = Date()
            samples.append((now, done))
            samples.removeAll { now.timeIntervalSince($0.time) > 30 }
            if let first = samples.first, now.timeIntervalSince(first.time) > 2 {
                let rate = Double(done - first.bytes) / now.timeIntervalSince(first.time)
                progress.secondsLeft = rate > 0 ? Double(total - done) / rate : nil
            }
        }
    }

    private func finish(_ result: ServerDownloadResult, items: [ServerDownloadItem]) {
        task = nil
        lastOutcomes = result.outcomes
        endHold()
        var saved = Set<String>()
        for (index, (item, outcome)) in zip(items, result.outcomes).enumerated() {
            switch outcome {
            case .saved:
                saved.insert(item.photo.id)
            case .failed(let reason):
                summary.failures.append(Failure(id: index, filename: item.photo.primary.name, reason: reason))
            case .notAttempted:
                summary.notAttemptedCount += 1
            }
        }
        summary.savedCount += saved.count
        switch result.stopReason {
        case .cancelled: summary.stopMessage = String(localized: "Stopped. Photos already imported stay in your library.", comment: "Download from server result after Cancel")
        case .error(let error): summary.stopMessage = error.localizedDescription
        case nil: break
        }
        if !saved.isEmpty { onSaved(saved) }
        stage = .finished
    }

    // MARK: Screen

    private func beginHold() {
        guard !isHolding else { return }
        isHolding = true
        screenHold.beginHold()
    }

    private func endHold() {
        guard isHolding else { return }
        isHolding = false
        screenHold.endHold()
    }
}
