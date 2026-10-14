import Foundation
import Observation

/// Downloads movies for offline (FS-23.01 §6): one at a time from a queue,
/// into `Movies/.incoming/<id>.part`, picking up at the bytes already
/// there, then checked against the source's size and moved to
/// `Movies/<id>/`. Subtitles beside the movie and its poster come along.
/// Plex and the background session join in plan tasks 12 and 32.
@MainActor
@Observable
final class MovieDownloadRunner {
    struct Environment: Sendable {
        /// A connected client for a folder source.
        var client: @Sendable (MovieSource) async throws -> any RemoteFileClient
        /// Bytes free for important use on the device.
        var freeSpace: @Sendable () -> Int64
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

    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    private(set) var current: String?
    /// Live bytes on disk per movie, for the bar between database writes.
    private(set) var liveBytes: [String: Int64] = [:]
    /// Bumped whenever a movie's state changes, so screens reload.
    private(set) var revision = 0

    init(store: MovieStore, files: MovieFileStore, environment: Environment, art: MoviePosterLoader? = nil) {
        self.store = store
        self.files = files
        self.environment = environment
        self.art = art
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
        if current == movieId { worker?.cancel() }
    }

    /// At launch: downloads that were running or waiting carry on, the
    /// sweep clears what no row explains (FS-23.05 §1).
    func resumeInterrupted() {
        try? files.prepare()
        let movies = (try? store.movies()) ?? []
        for id in files.sweep(movies: movies) {
            try? store.setState(id: id, .missing)
        }
        let waiting = movies
            .filter { ($0.state == .downloading || $0.state == .queued) && $0.downloadError == nil }
            .sorted { ($0.state == .downloading ? 0 : 1, $0.addedAt) < ($1.state == .downloading ? 0 : 1, $1.addedAt) }
        for movie in waiting where !queue.contains(movie.id) { queue.append(movie.id) }
        revision += 1
        runIfIdle()
    }

    /// Bytes to show for `movie` now.
    func bytes(for movie: Movie) -> Int64 {
        liveBytes[movie.id] ?? movie.downloadedBytes
    }

    /// Waits for the queue to empty — for tests.
    func waitUntilIdle() async {
        while let worker {
            await worker.value
            if self.worker == worker { break }
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
    /// fit either).
    private func run(_ movieId: String) async -> Bool {
        defer {
            liveBytes[movieId] = nil
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
        let saver = ProgressSaver(store: store, movieId: movieId, interval: environment.saveInterval)
        do {
            try files.prepare()
            let client = try await environment.client(source)
            let reached = try await client.resumeDownload(path, to: files.partFile(for: movieId)) { [weak self] bytes in
                saver.offer(bytes)
                Task { @MainActor in self?.liveBytes[movieId] = bytes }
            }
            guard reached == movie.byteCount else {
                files.removePart(for: movieId)
                fail(movie, String(localized: "The downloaded file doesn't match the one on \(movie.sourceName ?? source.name).", comment: "Movie download error: wrong size"))
                await client.disconnect()
                return true
            }
            let name = try files.finish(movieId, as: movie.originalFileName)
            try store.setLocalFileName(name.lastPathComponent, id: movieId)
            await fetchSubtitles(for: movie, client: client)
            await client.disconnect()
            await keepPoster(movieId)
            try store.setState(id: movieId, .onDevice, downloadedBytes: reached, error: nil)
        } catch is CancellationError {
            try? store.setState(id: movieId, .stream, downloadedBytes: files.partSize(for: movieId), error: nil)
        } catch {
            try? store.setState(id: movieId, .downloading, downloadedBytes: files.partSize(for: movieId), error: Self.message(error, source: movie.sourceName ?? source.name))
        }
        return true
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
