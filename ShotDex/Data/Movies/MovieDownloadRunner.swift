import Foundation
import Observation

/// Downloads movies for offline (FS-23.01 §6): one at a time from a queue,
/// into `Movies/.incoming/<id>.part`, picking up at the bytes already
/// there, then checked against the source's size and moved to
/// `Movies/<id>/`. Subtitles beside the movie and its poster come along.
///
/// Two ways to fetch (user decision 2026-10-14, AC-54): a connection with a
/// background session (WebDAV; Plex in plan task 32) hands the transfer to
/// iOS, which carries on with the device locked; SMB, SFTP and Files read
/// through the app's own client, so they need the app open — on iOS 26 a
/// continued-processing task buys time (`MovieBackgroundService`), and a
/// download the system stops picks up where it was when the app is back.
@MainActor
@Observable
final class MovieDownloadRunner {
    struct Environment: Sendable {
        /// A connected client for a folder source.
        var client: @Sendable (MovieSource) async throws -> any RemoteFileClient
        /// Bytes free for important use on the device.
        var freeSpace: @Sendable () -> Int64
        /// The request a background session should send for this movie from
        /// this byte, or nil when its source can't use one.
        var backgroundRequest: @Sendable (MovieSource, Movie, Int64) -> URLRequest? = { _, _, _ in nil }
        /// How often progress is written to the database (the bar itself
        /// moves on every chunk).
        var saveInterval: Duration = .seconds(2)
    }

    /// FS-23.01 §6: a movie needs its size plus this much free.
    static let headroom: Int64 = 1_000_000_000

    private let store: MovieStore
    let files: MovieFileStore
    private let environment: Environment
    private let art: MoviePosterLoader?
    private let transfer: MovieBackgroundTransfer?

    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    private(set) var current: String?
    /// The running download is in iOS's hands, not the app's.
    private(set) var currentIsBackground = false
    /// Live bytes on disk per movie, for the bar between database writes.
    private(set) var liveBytes: [String: Int64] = [:]
    /// Bumped whenever a movie's state changes, so screens reload.
    private(set) var revision = 0
    private var waiting: [String: CheckedContinuation<Error?, Never>] = [:]
    /// The current download is being stopped for the system, not by the
    /// user: it stays "downloading" and resumes when the app is back.
    private var isPausingForSystem = false

    /// Called when a download the app fetches itself starts (for the iOS 26
    /// continued-processing task).
    var onForegroundDownloadStarted: ((Movie) -> Void)?

    init(store: MovieStore, files: MovieFileStore, environment: Environment, art: MoviePosterLoader? = nil, transfer: MovieBackgroundTransfer? = nil) {
        self.store = store
        self.files = files
        self.environment = environment
        self.art = art
        self.transfer = transfer
        transfer?.onProgress = { [weak self] movieId, bytes in
            Task { @MainActor in self?.liveBytes[movieId] = bytes }
        }
        transfer?.onFinish = { [weak self] movieId, error in
            Task { @MainActor in self?.transferFinished(movieId, error: error) }
        }
    }

    /// Download to iPhone.
    func download(_ movieId: String) {
        guard !queue.contains(movieId), current != movieId else { return }
        try? store.setState(id: movieId, .queued, error: nil)
        queue.append(movieId)
        revision += 1
        runIfIdle()
    }

    /// Retry Download — the same, from the bytes already here.
    func retry(_ movieId: String) { download(movieId) }

    /// Stops a download (Remove Download while it runs); the part stays
    /// unless the caller removes it.
    func cancel(_ movieId: String) {
        queue.removeAll { $0 == movieId }
        guard current == movieId else { return }
        if currentIsBackground { transfer?.cancel(movieId: movieId) } else { worker?.cancel() }
    }

    /// Remove Download (FS-23.01 §6, AC-11): the file and any part go, the
    /// movie streams again from where it stopped; subtitles the user made
    /// stay on the device.
    func removeDownload(_ movie: Movie) {
        cancel(movie.id)
        if let file = files.file(for: movie) { try? FileManager.default.removeItem(at: file) }
        files.removePart(for: movie.id)
        let fetched = (try? store.removeDownload(id: movie.id)) ?? []
        for name in fetched where !name.isEmpty {
            try? FileManager.default.removeItem(at: files.directory(for: movie.id).appending(path: name))
        }
        try? FileManager.default.removeItem(at: files.directory(for: movie.id).appending(path: "poster.jpg"))
        liveBytes[movie.id] = nil
        revision += 1
    }

    /// The app is about to be suspended with no time granted: stop the
    /// download the app is reading itself at a clean point. A background
    /// transfer is left to iOS.
    func pauseForSystem() {
        guard current != nil, !currentIsBackground else { return }
        isPausingForSystem = true
        worker?.cancel()
    }

    /// At launch and when the app is back: downloads that were running or
    /// waiting carry on, the sweep clears what no row explains (FS-23.05 §1).
    /// Transfers iOS is still fetching are left alone.
    @discardableResult
    func resumeInterrupted() -> Task<Void, Never> {
        Task {
            let active = await transfer?.activeMovieIds() ?? []
            try? files.prepare()
            let movies = (try? store.movies()) ?? []
            if worker == nil {
                for id in files.sweep(movies: movies.filter { !active.contains($0.id) }) where !active.contains(id) {
                    try? store.setState(id: id, .missing)
                }
            }
            let waitingRows = movies
                .filter { ($0.state == .downloading || $0.state == .queued) && $0.downloadError == nil && !active.contains($0.id) }
                .sorted { ($0.state == .downloading ? 0 : 1, $0.addedAt) < ($1.state == .downloading ? 0 : 1, $1.addedAt) }
            for movie in waitingRows where !queue.contains(movie.id) && current != movie.id { queue.append(movie.id) }
            revision += 1
            runIfIdle()
        }
    }

    func movie(_ id: String) throws -> Movie? { try store.movie(id: id) }

    /// Bytes to show for `movie` now.
    func bytes(for movie: Movie) -> Int64 {
        liveBytes[movie.id] ?? movie.downloadedBytes
    }

    /// Whether a movie from this source keeps downloading with the app
    /// closed (FS-23.01 §6) — the row says "Keep ShotDex open" otherwise.
    func downloadsInBackground(_ source: MovieSource, _ movie: Movie) -> Bool {
        transfer != nil && environment.backgroundRequest(source, movie, 0) != nil
    }

    /// Waits for the queue to empty — for tests.
    func waitUntilIdle() async {
        while let running = worker {
            await running.value
            if worker == running { break }
        }
    }

    private func runIfIdle() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, let next = self.nextInQueue() {
                let keepGoing = await self.run(next)
                if !keepGoing { break }
            }
            self?.current = nil
            self?.currentIsBackground = false
            self?.worker = nil
        }
    }

    private func nextInQueue() -> String? {
        guard !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        current = next
        return next
    }

    /// One movie. false = stop the queue (no space: the next one would not
    /// fit either; or the app is being suspended).
    private func run(_ movieId: String) async -> Bool {
        defer {
            liveBytes[movieId] = nil
            currentIsBackground = false
            revision += 1
        }
        guard let movie = try? store.movie(id: movieId), movie.state != .onDevice else { return true }
        guard let sourceId = movie.sourceId, let source = try? store.source(id: sourceId),
              let path = movie.remotePath else {
            fail(movie, String(localized: "This movie has no source to download from.", comment: "Movie download error"))
            return true
        }
        let have = files.partSize(for: movieId)
        let needed = movie.byteCount - have + Self.headroom
        let free = environment.freeSpace()
        guard free >= needed else {
            let short = Double(needed - free) / 1_000_000_000
            try? store.setState(id: movieId, .stream, downloadedBytes: have, error: String(
                localized: "Not enough space on this device — about \(short.formatted(.number.precision(.fractionLength(1)))) GB needed.",
                comment: "Movie download refused: not enough free space"
            ))
            queue.removeAll()
            return false
        }
        try? store.setState(id: movieId, .downloading, downloadedBytes: have, error: nil)
        revision += 1
        try? files.prepare()

        if let transfer, let request = environment.backgroundRequest(source, movie, have) {
            currentIsBackground = true
            let error = await withCheckedContinuation { continuation in
                waiting[movieId] = continuation
                transfer.start(movieId: movieId, request: request, offset: have)
            }
            await complete(movieId, error: error)
            return true
        }

        onForegroundDownloadStarted?(movie)
        let saver = ProgressSaver(store: store, movieId: movieId, interval: environment.saveInterval)
        do {
            let client = try await environment.client(source)
            let reached = try await client.resumeDownload(path, to: files.partFile(for: movieId)) { [weak self] bytes in
                saver.offer(bytes)
                Task { @MainActor in self?.liveBytes[movieId] = bytes }
            }
            await finalize(movie, source: source, reached: reached, client: client)
            await client.disconnect()
        } catch is CancellationError {
            settleCancelled(movieId)
            if isPausingForSystem {
                isPausingForSystem = false
                return false
            }
        } catch {
            try? store.setState(id: movieId, .downloading, downloadedBytes: files.partSize(for: movieId), error: Self.message(error, source: movie.sourceName ?? source.name))
        }
        return true
    }

    /// A background transfer ended — for the download waiting on it, or one
    /// started before the app was quit and relaunched by iOS.
    private func transferFinished(_ movieId: String, error: Error?) {
        if let continuation = waiting.removeValue(forKey: movieId) {
            continuation.resume(returning: error)
        } else {
            Task { await complete(movieId, error: error) }
        }
    }

    private func complete(_ movieId: String, error: Error?) async {
        guard let movie = try? store.movie(id: movieId), let sourceId = movie.sourceId,
              let source = try? store.source(id: sourceId) else { return }
        liveBytes[movieId] = nil
        defer { revision += 1 }
        if error is CancellationError {
            settleCancelled(movieId)
            return
        }
        if let error {
            try? store.setState(id: movieId, .downloading, downloadedBytes: files.partSize(for: movieId), error: Self.message(error, source: movie.sourceName ?? source.name))
            return
        }
        let client = try? await environment.client(source)
        await finalize(movie, source: source, reached: files.partSize(for: movieId), client: client)
        await client?.disconnect()
    }

    /// Size check, then into `Movies/<id>/` with its subtitles and poster.
    private func finalize(_ movie: Movie, source: MovieSource, reached: Int64, client: (any RemoteFileClient)?) async {
        guard reached == movie.byteCount else {
            files.removePart(for: movie.id)
            fail(movie, String(localized: "The downloaded file doesn't match the one on \(movie.sourceName ?? source.name).", comment: "Movie download error: wrong size"))
            return
        }
        do {
            let file = try files.finish(movie.id, as: movie.originalFileName)
            try store.setLocalFileName(file.lastPathComponent, id: movie.id)
            if let client { await fetchSubtitles(for: movie, client: client) }
            await keepPoster(movie.id)
            try store.setState(id: movie.id, .onDevice, downloadedBytes: reached, error: nil)
        } catch {
            fail(movie, error.localizedDescription)
        }
    }

    /// Stopped by the user (back to Stream, the part kept for later) or by
    /// the system (still downloading, carries on when the app is back).
    private func settleCancelled(_ movieId: String) {
        let state: Movie.State = isPausingForSystem ? .downloading : .stream
        try? store.setState(id: movieId, state, downloadedBytes: files.partSize(for: movieId), error: nil)
    }

    private func fail(_ movie: Movie, _ message: String) {
        try? store.setState(id: movie.id, .stream, downloadedBytes: files.partSize(for: movie.id), error: message)
    }

    /// The row's red line (FS-23.01 §3).
    static func message(_ error: Error, source: String) -> String {
        switch error as? RemoteFileError {
        case .unreachable, .connectionLost, .localNetworkDenied:
            String(localized: "Download paused — \(source) unreachable", comment: "Movie download stopped: the source can't be reached")
        case .fileMissing:
            String(localized: "This movie is no longer on \(source).", comment: "Movie download stopped: the file is gone from the source")
        default:
            String(localized: "Download paused — \(error.localizedDescription)", comment: "Movie download stopped: other reason")
        }
    }

    /// Subtitle files beside the movie come along (small; FS-23.01 §6).
    private func fetchSubtitles(for movie: Movie, client: any RemoteFileClient) async {
        for subtitle in (try? store.subtitles(movieId: movie.id)) ?? [] where subtitle.fileName.isEmpty {
            guard let remote = subtitle.remotePath,
                  let size = try? await client.fileSize(at: remote), size > 0, size < 20_000_000,
                  let data = try? await client.readRange(remote, offset: 0, length: Int(size)),
                  let name = try? files.write(data, named: "\(subtitle.id).\(subtitle.format.rawValue)", for: movie.id) else { continue }
            var saved = subtitle
            saved.fileName = name
            try? store.saveSubtitle(saved)
        }
    }

    /// The poster seen in the grid stays with the movie offline.
    private func keepPoster(_ movieId: String) async {
        guard let art else { return }
        let cached = await art.cachedFile(for: movieId)
        guard let data = try? Data(contentsOf: cached) else { return }
        _ = try? files.write(data, named: "poster.jpg", for: movieId)
    }
}

/// Writes download progress to the database at most every `interval`.
private final class ProgressSaver: @unchecked Sendable {
    private let store: MovieStore
    private let movieId: String
    private let interval: Duration
    private let lock = NSLock()
    private var last = ContinuousClock.now

    init(store: MovieStore, movieId: String, interval: Duration) {
        self.store = store
        self.movieId = movieId
        self.interval = interval
    }

    func offer(_ bytes: Int64) {
        let due = lock.withLock { () -> Bool in
            guard ContinuousClock.now - last >= interval else { return false }
            last = .now
            return true
        }
        if due { try? store.setState(id: movieId, .downloading, downloadedBytes: bytes) }
    }
}
