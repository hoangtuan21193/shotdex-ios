import Foundation

/// Movie downloads iOS carries on with the app suspended or quit (FS-23.01
/// §6, AC-54): WebDAV now, Plex in plan task 32. Each task asks for the rest
/// of the file from the bytes already in the part (`Range`); when iOS hands
/// the rest over, it is appended to the part and the runner checks and files
/// it. iOS may relaunch the app in the background only to say a transfer
/// ended — the session is recreated under the same identifier and the
/// outcome still reaches the runner.
final class MovieBackgroundTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "com.hoangtuan.shotdex.movies.transfer"

    private let files: MovieFileStore
    /// The connection a movie downloads from — for its saved certificate.
    private let server: @Sendable (String) -> FileServer?
    private let lock = NSLock()
    private var failures: [Int: Error] = [:]
    private var _session: URLSession?

    /// Bytes in the part now, per movie.
    var onProgress: (@Sendable (String, Int64) -> Void)?
    /// The transfer ended: nil = the part holds everything iOS fetched.
    var onFinish: (@Sendable (String, Error?) -> Void)?

    init(files: MovieFileStore, server: @escaping @Sendable (String) -> FileServer?, configuration: URLSessionConfiguration? = nil) {
        self.files = files
        self.server = server
        super.init()
        let configuration = configuration ?? {
            let background = URLSessionConfiguration.background(withIdentifier: Self.identifier)
            background.sessionSendsLaunchEvents = true
            background.isDiscretionary = false
            return background
        }()
        _session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    private var session: URLSession { lock.withLock { _session! } }

    func start(movieId: String, request: URLRequest, offset: Int64) {
        let task = session.downloadTask(with: request)
        task.taskDescription = "\(movieId)|\(offset)"
        task.resume()
    }

    /// Movies iOS is still fetching — not to be started twice at launch.
    func activeMovieIds() async -> Set<String> {
        Set(await session.allTasks.compactMap { Self.parse($0.taskDescription)?.movieId })
    }

    func cancel(movieId: String) {
        session.getAllTasks { tasks in
            for task in tasks where Self.parse(task.taskDescription)?.movieId == movieId { task.cancel() }
        }
    }

    static func parse(_ description: String?) -> (movieId: String, offset: Int64)? {
        guard let parts = description?.split(separator: "|"), parts.count == 2, let offset = Int64(parts[1]) else { return nil }
        return (String(parts[0]), offset)
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (movieId, offset) = Self.parse(downloadTask.taskDescription) else { return }
        onProgress?(movieId, offset + totalBytesWritten)
    }

    /// Runs before `location` is deleted: the bytes go into the part here.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (movieId, offset) = Self.parse(downloadTask.taskDescription) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            switch status {
            case 206 where offset > 0:
                try Self.append(location, to: files.partFile(for: movieId))
            case 200, 206:
                // From byte 0 (a first download, or a server that ignored Range).
                try? FileManager.default.createDirectory(at: files.incoming, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: files.partFile(for: movieId))
                try FileManager.default.moveItem(at: location, to: files.partFile(for: movieId))
            case 401:
                throw RemoteFileError.authenticationFailed
            case 404:
                throw RemoteFileError.fileMissing(downloadTask.originalRequest?.url?.lastPathComponent ?? "")
            default:
                throw RemoteFileError.other(HTTPURLResponse.localizedString(forStatusCode: status))
            }
        } catch {
            lock.withLock { failures[downloadTask.taskIdentifier] = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (movieId, _) = Self.parse(task.taskDescription) else { return }
        let failure = lock.withLock { failures.removeValue(forKey: task.taskIdentifier) }
        onFinish?(movieId, failure ?? error.map(Self.mapped))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let (movieId, _) = Self.parse(task.taskDescription), let server = server(movieId) else {
            return (.performDefaultHandling, nil)
        }
        let (answer, rejection) = WebDAVFileClient.trust(challenge, server: server)
        if let rejection { lock.withLock { failures[task.taskIdentifier] = rejection } }
        return answer
    }

    /// iOS woke the app for this session; it may suspend it again once the
    /// handler it left is called.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            BackgroundURLSessionEvents.complete(Self.identifier)
        }
    }

    private static func mapped(_ error: Error) -> Error {
        guard let url = error as? URLError else { return error }
        switch url.code {
        case .cancelled: return CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut, .cannotFindHost:
            return RemoteFileError.unreachable(host: url.failingURL?.host() ?? "")
        default: return error
        }
    }

    /// Streams `source` onto the end of `part` — never both in memory.
    static func append(_ source: URL, to part: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        if !FileManager.default.fileExists(atPath: part.path) {
            FileManager.default.createFile(atPath: part.path, contents: nil)
        }
        let output = try FileHandle(forWritingTo: part)
        defer { try? output.close() }
        try output.seekToEnd()
        while let chunk = try input.read(upToCount: 4 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }
}

/// The completion handlers iOS leaves when it wakes the app for a
/// background session (`application(_:handleEventsForBackgroundURLSession:)`).
@MainActor
enum BackgroundURLSessionEvents {
    private static var handlers: [String: () -> Void] = [:]

    static func store(_ handler: @escaping () -> Void, for identifier: String) {
        handlers[identifier] = handler
    }

    static func complete(_ identifier: String) {
        handlers.removeValue(forKey: identifier)?()
    }
}
