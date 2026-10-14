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
    /// The task this process started last per movie: only its outcome
    /// reaches the runner. A task from before a relaunch (none here) reports
    /// too; one replaced by a newer task does not.
    private var started: [String: Int] = [:]
    /// Tasks cancelled because an older transfer took over: they say nothing.
    private var superseded: Set<Int> = []
    /// What iOS kept of a stopped transfer — after a force quit it arrives
    /// with the next launch — so the next try carries on from there instead
    /// of from the part. Memory only: it holds the request, and a Plex
    /// request carries the token (never on disk).
    private var resumeData: [String: (offset: Int64, data: Data)] = [:]

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
        let kept = lock.withLock { resumeData.removeValue(forKey: movieId) }
        let task = kept.flatMap { $0.offset == offset ? session.downloadTask(withResumeData: $0.data) : nil }
            ?? session.downloadTask(with: request)
        task.taskDescription = "\(movieId)|\(offset)"
        lock.withLock { started[movieId] = task.taskIdentifier }
        task.resume()
    }

    /// Whether a stopped transfer of this movie can carry on where it was.
    func canResume(movieId: String, offset: Int64) -> Bool {
        lock.withLock { resumeData[movieId]?.offset == offset }
    }

    /// Movies iOS is still fetching — not to be started twice at launch.
    func activeMovieIds() async -> Set<String> {
        Set(await session.allTasks.compactMap { Self.parse($0.taskDescription)?.movieId })
    }

    func cancel(movieId: String) {
        lock.withLock { _ = resumeData.removeValue(forKey: movieId) }
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

    /// A transfer carried on from what iOS kept: the bar starts where it was.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        guard let (movieId, offset) = Self.parse(downloadTask.taskDescription) else { return }
        onProgress?(movieId, offset + fileOffset)
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
        guard let (movieId, offset) = Self.parse(task.taskDescription) else { return }
        let kept = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let failure = lock.withLock { failures.removeValue(forKey: task.taskIdentifier) }
        enum Outcome { case report, ignore, takeOver(Int) }
        let outcome: Outcome = lock.withLock {
            if superseded.remove(task.taskIdentifier) != nil { return .ignore }
            switch started[movieId] {
            case task.taskIdentifier?:
                started[movieId] = nil
                if let kept { resumeData[movieId] = (offset, kept) }
                return .report
            case nil:
                // From before a relaunch (a force quit cancels it): what iOS
                // kept is used by the try the runner starts for it.
                if let kept { resumeData[movieId] = (offset, kept) }
                return .report
            case let newer?:
                // The launch already restarted this movie from the part
                // before this old transfer reported; what it kept is further
                // along, so it takes over.
                guard let kept else { return .ignore }
                resumeData[movieId] = (offset, kept)
                return .takeOver(newer)
            }
        }
        switch outcome {
        case .report:
            onFinish?(movieId, failure ?? error.map(Self.mapped))
        case .ignore:
            break
        case .takeOver(let newer):
            session.getAllTasks { [weak self] tasks in
                guard let self, let fresh = tasks.first(where: { $0.taskIdentifier == newer }),
                      Self.parse(fresh.taskDescription)?.offset == offset,
                      let data = lock.withLock({ self.resumeData.removeValue(forKey: movieId) })?.data else { return }
                let resumed = session.downloadTask(withResumeData: data)
                resumed.taskDescription = fresh.taskDescription
                lock.withLock {
                    self.started[movieId] = resumed.taskIdentifier
                    self.superseded.insert(fresh.taskIdentifier)
                }
                fresh.cancel()
                resumed.resume()
            }
        }
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
