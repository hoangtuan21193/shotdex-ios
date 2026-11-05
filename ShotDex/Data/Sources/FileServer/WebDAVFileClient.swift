import CryptoKit
import Foundation
import Security

/// `RemoteFileClient` over WebDAV (FS-15.05): `URLSession`, no library.
/// Paths are relative to the connection's base path (`share`).
///
/// A certificate the system trusts is accepted; one it doesn't (a NAS's
/// self-signed certificate) is checked against the fingerprint the user
/// trusted, the way SFTP host keys are.
final class WebDAVFileClient: NSObject, RemoteFileClient, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let server: FileServer
    private let password: String
    private let configuration: URLSessionConfiguration
    private var session: URLSession!
    private let lock = NSLock()
    /// Why the last request's TLS handshake was refused, if it was.
    private var trustRejection: RemoteFileError?
    /// How this server took a file's dates the first time one held, or
    /// that none did (FS-19.08 §6e); nil until a file has been tried.
    private var datesVerdict: DatesVerdict?

    /// `configuration` is the tests' seam: a stub `URLProtocol` stands in
    /// for the server there.
    init(server: FileServer, password: String, configuration: URLSessionConfiguration = .ephemeral) {
        self.server = server
        self.password = password
        self.configuration = configuration
        super.init()
        configuration.timeoutIntervalForRequest = 30
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    // MARK: URLs

    private var baseURL: URL {
        var components = URLComponents()
        components.scheme = server.usesTLS ? "https" : "http"
        components.host = server.host
        if server.port != server.defaultPort { components.port = server.port }
        components.path = "/" + ServerUploadPath.normalizedFolder(server.share)
        return components.url!
    }

    private func url(_ path: String, isDirectory: Bool = false) -> URL {
        var url = baseURL
        for component in ServerUploadPath.normalizedFolder(path).split(separator: "/") {
            url.append(path: String(component), directoryHint: .notDirectory)
        }
        return isDirectory ? url.appending(path: "", directoryHint: .isDirectory) : url
    }

    private func request(_ method: String, _ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        let token = Data("\(server.username):\(password)".utf8).base64EncodedString()
        // Preemptive Basic over HTTPS; over HTTP the form already warned.
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: RemoteFileClient

    func connect() async throws {
        let (_, response) = try await send(propfind(url("", isDirectory: true), depth: 0))
        try check(response, path: server.share, allow: [207])
    }

    func disconnect() async {
        session.finishTasksAndInvalidate()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func entries(in directory: String) async throws -> [RemoteEntry] {
        let target = url(directory, isDirectory: true)
        let (data, response) = try await send(propfind(target, depth: 1))
        if (response as? HTTPURLResponse)?.statusCode == 404 { return [] }
        try check(response, path: directory, allow: [207])
        return PropfindParser.entries(PropfindParser.parse(data), inFolder: target.path(percentEncoded: false))
    }

    func fileSize(at path: String) async throws -> Int64? {
        let (data, response) = try await send(propfind(url(path), depth: 0))
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        try check(response, path: path, allow: [207])
        guard let item = PropfindParser.parse(data).first, !item.isCollection else { return nil }
        return item.size
    }

    func directoryExists(_ path: String) async throws -> Bool {
        let (data, response) = try await send(propfind(url(path, isDirectory: true), depth: 0))
        if (response as? HTTPURLResponse)?.statusCode == 404 { return false }
        try check(response, path: path, allow: [207])
        return PropfindParser.parse(data).first?.isCollection ?? false
    }

    func fileNames(in directory: String) async throws -> Set<String> {
        Set(try await entries(in: directory).filter { !$0.isDirectory }.map(\.name))
    }

    func folderNames(in directory: String) async throws -> Set<String> {
        Set(try await entries(in: directory).filter(\.isDirectory).map(\.name))
    }

    func createDirectory(_ path: String) async throws {
        var current = ""
        for component in ServerUploadPath.normalizedFolder(path).split(separator: "/") {
            current = ServerUploadPath.join(current, String(component))
            let (_, response) = try await send(request("MKCOL", url(current, isDirectory: true)))
            // 405: already there.
            try check(response, path: current, allow: [200, 201, 204, 405])
        }
    }

    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        var put = request("PUT", url(path))
        put.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        // Streamed from the file with its length up front: never the whole
        // RAW in memory, and no chunked encoding (some servers refuse it).
        let size = (try localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        put.setValue(String(size), forHTTPHeaderField: "Content-Length")
        put.httpBodyStream = InputStream(url: localURL)
        let delegate = ProgressDelegate(onSent: progress)
        let (_, response) = try await perform { try await self.session.data(for: put, delegate: delegate) }
        try check(response, path: path, allow: [200, 201, 204])
    }

    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexDAV-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        return try await download(path, to: temporary, progress: progress)
    }

    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let delegate = ProgressDelegate(onReceived: progress)
        let (location, response) = try await perform { try await self.session.download(for: self.request("GET", self.url(path)), delegate: delegate) }
        try check(response, path: path, allow: [200])
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: location, to: localURL)
        // The task's last write callback does not always come before the
        // reply: the file on disk is what was read. Callers check this
        // count against the listed size (the Common Photos verifier skips a
        // file read short as changed), so it must end at the whole file.
        if let size = try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize { progress(Int64(size)) }
        return try FileChecksum.sha256(of: localURL)
    }

    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        var get = request("GET", url(path))
        get.setValue("bytes=\(offset)-\(offset + Int64(length) - 1)", forHTTPHeaderField: "Range")
        let (bytes, response) = try await perform { try await self.session.bytes(for: get) }
        try check(response, path: path, allow: [200, 206])
        // A server that ignores Range sends the whole file from byte 0; one
        // that answers 206 must answer for the bytes asked, or the caller
        // would hash the wrong part of the file.
        let http = response as? HTTPURLResponse
        if http?.statusCode == 206, let start = Self.rangeStart(http?.value(forHTTPHeaderField: "Content-Range")), start != offset {
            bytes.task.cancel()
            throw RemoteFileError.other("server sent bytes from \(start), not \(offset)")
        }
        let skip = http?.statusCode == 200 ? Int(offset) : 0
        var result = Data()
        result.reserveCapacity(length)
        var skipped = 0
        for try await byte in bytes {
            if skipped < skip { skipped += 1; continue }
            result.append(byte)
            if result.count >= length { break }
        }
        bytes.task.cancel()
        return result
    }

    /// The first byte of a `Content-Range: bytes 100-199/1000` answer.
    static func rangeStart(_ header: String?) -> Int64? {
        guard let header, let range = header.split(separator: " ").last,
              let first = range.split(separator: "-").first else { return nil }
        return Int64(first)
    }

    func move(_ source: String, to destination: String) async throws {
        var move = request("MOVE", url(source))
        move.setValue(url(destination).absoluteString, forHTTPHeaderField: "Destination")
        move.setValue("F", forHTTPHeaderField: "Overwrite")
        let (_, response) = try await send(move)
        try check(response, path: destination, allow: [201, 204])
    }

    /// RFC 4918 §9.8. 201 or 204: copied. A wrong password or a full disk
    /// stops the run as any write would; every other answer (405, 501, 403,
    /// 423, 502, a proxy's 400…) is a no, and the photo goes the long way —
    /// falling back costs time, failing would cost the photo.
    func copyOnServer(_ source: String, to destination: String) async throws -> Bool {
        var copy = request("COPY", url(source))
        copy.setValue(url(destination).absoluteString, forHTTPHeaderField: "Destination")
        copy.setValue("T", forHTTPHeaderField: "Overwrite")
        copy.setValue("0", forHTTPHeaderField: "Depth")
        // The reply comes only when the NAS has copied the whole file: a
        // 4 GB video on one disk takes minutes, not the 30 s of a request.
        copy.timeoutInterval = 3600
        let (_, response) = try await send(copy)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 201, 204: return true
        case 401, 507, nil: try check(response, path: destination, allow: []); return false
        default: return false
        }
    }

    func remove(_ path: String) async throws {
        let (_, response) = try await send(request("DELETE", url(path)))
        try check(response, path: path, allow: [200, 204, 404])
    }

    /// RFC 4331 quota properties on the folder; servers without quotas
    /// leave them out and the footer shows no storage line.
    func storageSpace(at path: String) async throws -> StorageSpace? {
        var request = request("PROPFIND", url(path, isDirectory: true))
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
            <?xml version="1.0" encoding="utf-8"?>
            <d:propfind xmlns:d="DAV:"><d:prop><d:quota-available-bytes/><d:quota-used-bytes/></d:prop></d:propfind>
            """.utf8)
        guard let (data, response) = try? await send(request),
              (response as? HTTPURLResponse)?.statusCode == 207 else { return nil }
        return StorageSpaceReading.webdavQuota(data)
    }

    // MARK: File info (FS-19.08 §6e)

    /// The ways WebDAV servers take a file's dates, in the order they are
    /// tried: IIS and wsgidav's Windows emulation honour the `Win32*`
    /// properties, a server that lets `getlastmodified` be written takes
    /// that, Nextcloud and ownCloud take `lastmodified` as Unix seconds. Each
    /// is its own `PROPPATCH` — a protected property's 403 would turn the
    /// others in the same request into 424 (RFC 4918 §9.2).
    private enum DatesMethod: CaseIterable {
        case win32, getLastModified, lastModifiedSeconds
    }

    private enum DatesVerdict {
        case takes(DatesMethod)
        /// Every way failed on this many files in a row; at two the server
        /// counts as refusing — one slow read-back is not a verdict.
        case failed(Int)
        case refuses
    }

    func fileInfo(at path: String) async throws -> RemoteFileInfo? {
        let (data, response) = try await send(propfind(url(path), depth: 0))
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        try check(response, path: path, allow: [207])
        guard let item = PropfindParser.parse(data).first, !item.isCollection else { return nil }
        return RemoteFileInfo(modified: item.modified ?? .distantPast)
    }

    /// Whether a date held is read back, never taken from the 207: Apache
    /// `mod_dav` (Synology, QNAP) stores `Win32*` as dead properties and
    /// answers 200 with the date unchanged. The first file tries each way;
    /// the rest of the connection uses the one that held, or none.
    func setFileInfo(_ info: RemoteFileInfo, at path: String) async throws -> FileInfoSupport {
        switch lock.withLock({ datesVerdict }) {
        case .refuses:
            return .unsupported
        case .takes(let method):
            try await patchDates(info, at: path, method)
            return .applied
        case nil, .failed:
            // A file already at that time proves nothing either way.
            if let before = try await fileInfo(at: path), before.hasSameModified(as: info) { return .applied }
            for method in DatesMethod.allCases {
                try await patchDates(info, at: path, method)
                if let now = try await fileInfo(at: path), now.hasSameModified(as: info) {
                    lock.withLock { datesVerdict = .takes(method) }
                    return .applied
                }
            }
            lock.withLock {
                if case .failed(let count) = datesVerdict, count >= 1 {
                    datesVerdict = .refuses
                } else {
                    datesVerdict = .failed(1)
                }
            }
            return .unsupported
        }
    }

    private func patchDates(_ info: RemoteFileInfo, at path: String, _ method: DatesMethod) async throws {
        let props: String
        switch method {
        case .win32:
            let created = info.created.map { "<z:Win32CreationTime>\(Self.httpDate($0))</z:Win32CreationTime>" } ?? ""
            props = "<z:Win32LastModifiedTime>\(Self.httpDate(info.modified))</z:Win32LastModifiedTime>" + created
        case .getLastModified:
            props = "<d:getlastmodified>\(Self.httpDate(info.modified))</d:getlastmodified>"
        case .lastModifiedSeconds:
            props = "<d:lastmodified>\(Int(info.modified.timeIntervalSince1970))</d:lastmodified>"
        }
        var patch = request("PROPPATCH", url(path))
        patch.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        patch.httpBody = Data("""
            <?xml version="1.0" encoding="utf-8"?>
            <d:propertyupdate xmlns:d="DAV:" xmlns:z="urn:schemas-microsoft-com:"><d:set><d:prop>\(props)</d:prop></d:set></d:propertyupdate>
            """.utf8)
        let (_, response) = try await send(patch)
        // A lost login throws (a caller that swallows it meets the 401 again
        // on its next request); any other answer is the re-read's to judge.
        if (response as? HTTPURLResponse)?.statusCode == 401 { try check(response, path: path, allow: []) }
    }

    /// RFC 1123 in GMT, as WebDAV dates are written.
    private static func httpDate(_ date: Date) -> String {
        date.formatted(Date.VerbatimFormatStyle(
            format: "\(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) GMT",
            locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt, calendar: Calendar(identifier: .gregorian)))
    }

    func removeEmptyDirectory(_ path: String) async throws {
        // A collection's DELETE takes what is in it: refused unless the
        // listing just now found it empty (FS-19.08 §6e, Undo's folders).
        guard try await entries(in: path).isEmpty else { throw RemoteFileError.other("not empty") }
        let (_, response) = try await send(request("DELETE", url(path, isDirectory: true)))
        try check(response, path: path, allow: [200, 204, 404])
    }

    /// A collection's DELETE takes everything in it (RFC 4918 §9.6.1); 207
    /// means part of it stayed.
    func removeFolderTree(_ path: String) async throws {
        let (_, response) = try await send(request("DELETE", url(path, isDirectory: true)))
        if (response as? HTTPURLResponse)?.statusCode == 207 { throw RemoteFileError.permissionDenied(path) }
        try check(response, path: path, allow: [200, 204, 404])
    }

    // MARK: Requests

    private func propfind(_ url: URL, depth: Int) -> URLRequest {
        var request = request("PROPFIND", url)
        request.setValue(String(depth), forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
            <?xml version="1.0" encoding="utf-8"?>
            <d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>
            """.utf8)
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await perform { try await self.session.data(for: request) }
    }

    /// Runs a request and turns transport failures into the user's terms —
    /// a refused certificate into the trust verdict the delegate recorded.
    private func perform<T>(_ work: () async throws -> T) async throws -> T {
        lock.withLock { trustRejection = nil }
        do {
            return try await work()
        } catch let error as CancellationError {
            throw error
        } catch {
            if let rejection = lock.withLock({ trustRejection }) { throw rejection }
            if (error as? URLError)?.code == .cancelled, Task.isCancelled { throw CancellationError() }
            throw mapNetworkError(error, host: server.host)
        }
    }

    private func check(_ response: URLResponse, path: String, allow: Set<Int>) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw RemoteFileError.connectionLost }
        if allow.contains(status) { return }
        switch status {
        case 401: throw RemoteFileError.authenticationFailed
        case 403: throw RemoteFileError.permissionDenied(path)
        case 404, 409: throw RemoteFileError.folderMissing(path)
        case 412: throw RemoteFileError.other(String(localized: "\(path) already exists on the server.", comment: "WebDAV: move refused because the destination exists"))
        case 507: throw RemoteFileError.serverFull
        default: throw RemoteFileError.other(HTTPURLResponse.localizedString(forStatusCode: status))
        }
    }

    // MARK: Trust

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let (disposition, rejection) = Self.trust(challenge, server: server)
        if let rejection { lock.withLock { trustRejection = rejection } }
        return disposition
    }

    /// The server-trust answer for a connection's saved identity: a real
    /// certificate passes, a self-signed one passes only if it is the one
    /// the user trusted.
    static func trust(_ challenge: URLAuthenticationChallenge, server: FileServer)
        -> ((URLSession.AuthChallengeDisposition, URLCredential?), RemoteFileError?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else { return ((.performDefaultHandling, nil), nil) }
        // The system trusts it (a real certificate): nothing to ask.
        if SecTrustEvaluateWithError(trust, nil) { return ((.useCredential, URLCredential(trust: trust)), nil) }
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            return ((.cancelAuthenticationChallenge, nil), nil)
        }
        let offered = TLSCertificateTrust.fingerprint(ofCertificate: SecCertificateCopyData(leaf) as Data)
        switch HostKeyTrust.evaluate(offered: offered, saved: server.trustedFingerprint) {
        case .trusted:
            return ((.useCredential, URLCredential(trust: trust)), nil)
        case .untrusted(let fingerprint):
            return ((.cancelAuthenticationChallenge, nil), .hostKeyUntrusted(fingerprint: fingerprint))
        case .changed(let fingerprint):
            return ((.cancelAuthenticationChallenge, nil), .hostKeyChanged(host: server.host, fingerprint: fingerprint))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            return await urlSession(session, didReceive: challenge)
        }
        // Digest (or Basic after a 401): answer once, then give up so a wrong
        // password surfaces as 401 instead of looping.
        guard challenge.previousFailureCount == 0 else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(user: server.username, password: password, persistence: .none))
    }
}

/// Per-request progress for uploads and downloads.
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    let onSent: (@Sendable (Int64) -> Void)?
    let onReceived: (@Sendable (Int64) -> Void)?

    init(onSent: (@Sendable (Int64) -> Void)? = nil, onReceived: (@Sendable (Int64) -> Void)? = nil) {
        self.onSent = onSent
        self.onReceived = onReceived
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        onSent?(totalBytesSent)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onReceived?(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
