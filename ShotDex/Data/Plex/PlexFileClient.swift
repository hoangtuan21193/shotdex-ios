import Foundation

/// A Plex server read like a file server (FS-23.07 §2, S3 §4): part keys are
/// the paths, bytes come by HTTP Range with the token in a header — so a
/// Plex movie streams through `RemoteMovieStream` and downloads through
/// the same runner as a NAS movie, and VLC never sees the token. Read only.
final class PlexFileClient: RemoteFileClient, @unchecked Sendable {
    let base: URL
    let token: String
    let session: URLSession
    let client: PlexClient

    init(base: URL, token: String, session: URLSession = .shared, client: PlexClient = PlexClient()) {
        self.base = base
        self.token = token
        self.session = session
        self.client = client
    }

    enum Failure: Error { case readOnly }

    func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: base)?.absoluteURL ?? base.appending(path: path))
        request.timeoutInterval = 30
        client.authorize(&request, token: token)
        return request
    }

    func connect() async throws {}
    func disconnect() async {}

    func fileSize(at path: String) async throws -> Int64? {
        var request = request(path)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 { throw PlexClient.Failure.signedOut }
        if http.statusCode == 404 { throw RemoteFileError.fileMissing(path) }
        // `Content-Range: bytes 0-0/54321`
        if let range = http.value(forHTTPHeaderField: "Content-Range"), let total = range.split(separator: "/").last.flatMap({ Int64($0) }) {
            return total
        }
        return http.expectedContentLength > 0 ? http.expectedContentLength : nil
    }

    func readRange(_ path: String, offset: Int64, length: Int) async throws -> Data {
        guard length > 0 else { return Data() }
        var request = request(path)
        request.setValue("bytes=\(offset)-\(offset + Int64(length) - 1)", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw PlexClient.Failure.signedOut }
        if status == 404 { throw RemoteFileError.fileMissing(path) }
        guard status == 206 || status == 200 else { throw PlexClient.Failure.badResponse }
        // A server that ignored the Range sent the whole file: take the part asked.
        if status == 200, data.count > length {
            let start = Int(min(offset, Int64(data.count)))
            return data.subdata(in: start..<min(data.count, start + length))
        }
        return data
    }

    func download(_ path: String, to localURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let (temporary, response) = try await session.download(for: request(path))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw PlexClient.Failure.signedOut }
        guard (200..<300).contains(status) else { throw RemoteFileError.fileMissing(path) }
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: temporary, to: localURL)
        progress(Int64((try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value ?? 0))
        return ""
    }

    func directoryExists(_ path: String) async throws -> Bool { false }
    func fileNames(in directory: String) async throws -> Set<String> { [] }
    func folderNames(in directory: String) async throws -> Set<String> { [] }
    func entries(in directory: String) async throws -> [RemoteEntry] { [] }
    func createDirectory(_ path: String) async throws { throw Failure.readOnly }
    func upload(_ localURL: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws { throw Failure.readOnly }
    func sha256(of path: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> String { throw Failure.readOnly }
    func move(_ source: String, to destination: String) async throws { throw Failure.readOnly }
    func remove(_ path: String) async throws { throw Failure.readOnly }
    func removeEmptyDirectory(_ path: String) async throws { throw Failure.readOnly }
}
