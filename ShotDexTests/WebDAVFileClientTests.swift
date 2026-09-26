import CryptoKit
import Foundation
import Testing
@testable import ShotDex

/// A WebDAV server in memory, behind `URLProtocol`: PROPFIND, MKCOL, PUT,
/// GET (with Range), MOVE, DELETE — enough for the client's whole contract.
final class StubWebDAVProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var files: [String: Data] = [:]
    nonisolated(unsafe) static var folders: Set<String> = [""]

    static func reset() {
        lock.withLock { files = [:]; folders = [""] }
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "dav.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// `/base/a/b.CR3` → `a/b.CR3` under the connection's `base` path.
    private static func key(_ url: URL) -> String {
        let parts = url.path(percentEncoded: false).split(separator: "/").dropFirst()
        return parts.joined(separator: "/")
    }

    override func startLoading() {
        guard let url = request.url, let method = request.httpMethod else { return }
        let key = Self.key(url)
        var status = 200
        var body = Data()
        var headers: [String: String] = [:]
        Self.lock.withLock {
            switch method {
            case "PROPFIND":
                let depth = request.value(forHTTPHeaderField: "Depth") ?? "1"
                if Self.folders.contains(key) {
                    status = 207
                    var rows = [Self.row(href: url.path(percentEncoded: true), collection: true, size: 0)]
                    if depth == "1" {
                        for folder in Self.folders where !folder.isEmpty && ServerUploadPath.parent(of: folder) == key {
                            rows.append(Self.row(href: "/base/" + Self.encode(folder) + "/", collection: true, size: 0))
                        }
                        for (path, data) in Self.files where ServerUploadPath.parent(of: path) == key {
                            rows.append(Self.row(href: "/base/" + Self.encode(path), collection: false, size: data.count))
                        }
                    }
                    body = Data("<?xml version=\"1.0\"?><d:multistatus xmlns:d=\"DAV:\">\(rows.joined())</d:multistatus>".utf8)
                } else if let data = Self.files[key] {
                    status = 207
                    body = Data("<d:multistatus xmlns:d=\"DAV:\">\(Self.row(href: url.path(percentEncoded: true), collection: false, size: data.count))</d:multistatus>".utf8)
                } else {
                    status = 404
                }
            case "MKCOL":
                if Self.folders.contains(key) { status = 405 }
                else if !Self.folders.contains(ServerUploadPath.parent(of: key)) { status = 409 }
                else { Self.folders.insert(key); status = 201 }
            case "PUT":
                guard Self.folders.contains(ServerUploadPath.parent(of: key)) else { status = 409; break }
                Self.files[key] = Self.readBody(request)
                status = 201
            case "GET":
                guard let data = Self.files[key] else { status = 404; break }
                if let range = request.value(forHTTPHeaderField: "Range"),
                   let bounds = range.split(separator: "=").last?.split(separator: "-"), bounds.count == 2,
                   let start = Int(bounds[0]), let end = Int(bounds[1]) {
                    status = 206
                    body = data.subdata(in: min(start, data.count)..<min(end + 1, data.count))
                } else {
                    body = data
                }
            case "MOVE":
                guard let destination = request.value(forHTTPHeaderField: "Destination").flatMap(URL.init(string:)),
                      let data = Self.files[key] else { status = 404; break }
                let target = Self.key(destination)
                if Self.files[target] != nil, request.value(forHTTPHeaderField: "Overwrite") == "F" { status = 412; break }
                Self.files[target] = data
                Self.files[key] = nil
                status = 201
            case "DELETE":
                status = Self.files.removeValue(forKey: key) == nil ? 404 : 204
            default:
                status = 405
            }
        }
        headers["Content-Length"] = String(body.count)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func encode(_ path: String) -> String {
        path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
    }

    private static func row(href: String, collection: Bool, size: Int) -> String {
        """
        <d:response><d:href>\(href)</d:href><d:propstat><d:prop>\
        <d:resourcetype>\(collection ? "<d:collection/>" : "")</d:resourcetype>\
        <d:getcontentlength>\(size)</d:getcontentlength>\
        <d:getlastmodified>Sat, 26 Sep 2026 10:00:00 GMT</d:getlastmodified>\
        </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        """
    }

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// FS-15.05 §2 — the WebDAV client against the stub server.
@Suite(.serialized) struct WebDAVFileClientTests {
    private func client() -> WebDAVFileClient {
        StubWebDAVProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubWebDAVProtocol.self]
        let server = FileServer(name: "DAV", transferProtocol: .webdav, host: "dav.test", username: "me", share: "base")
        return WebDAVFileClient(server: server, password: "pw", configuration: configuration)
    }

    /// AC-31: the upload session's contract — part file, read-back checksum,
    /// rename, record — holds over WebDAV.
    @Test func sessionContract() async throws {
        let dav = client()
        let fixture = UploadFixture(count: 3, bytes: 300_000)
        let recorder = UploadRecorder()
        let session = ServerUploadSession(
            client: dav, exporter: fixture.exporter, serverId: "S1", serverName: "DAV",
            workDirectory: fixture.workDirectory,
            resolveConflict: { _ in .init(choice: .skip) },
            record: { recorder.record($0) }
        )
        let result = await session.run(fixture.items)
        #expect(result.outcomes.allSatisfy { if case .uploaded = $0 { true } else { false } })
        let stored = StubWebDAVProtocol.lock.withLock { StubWebDAVProtocol.files }
        #expect(Set(stored.keys) == Set(fixture.items.map(\.remotePath)))
        for (index, item) in fixture.items.enumerated() {
            #expect(stored[item.remotePath] == fixture.data(index))
        }
        #expect(recorder.records.count == 3)
        #expect(recorder.records.allSatisfy { $0.sha256.count == 64 })

        // The same files read back: range, listing, download.
        let head = try await dav.readRange(fixture.items[0].remotePath, offset: 0, length: 1024)
        #expect(head == fixture.data(0).prefix(1024))
        let listed = try await dav.entries(in: "Photos/2026/2026-09-24")
        #expect(Set(listed.map(\.name)) == Set(fixture.items.map(\.file.filename)))
        #expect(listed.allSatisfy { $0.size == 300_000 && $0.modified != nil })
    }

    /// AC-32.
    @Test func propfindParsing() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response><D:href>/remote.php/dav/files/me/Photos/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
          <D:response><D:href>/remote.php/dav/files/me/Photos/2025/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
          <D:response><D:href>/remote.php/dav/files/me/Photos/Tr%C3%A0ng%20An/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
          <D:response><D:href>https://cloud.example.com/remote.php/dav/files/me/Photos/Old/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
          <D:response><D:href>/remote.php/dav/files/me/Photos/IMG%201.CR3</D:href><D:propstat><D:prop><D:resourcetype/><D:getcontentlength>31900000</D:getcontentlength><D:getlastmodified>Sat, 26 Sep 2026 10:00:00 GMT</D:getlastmodified></D:prop></D:propstat></D:response>
          <D:response><D:href>/remote.php/dav/files/me/Photos/%E1%BA%A2nh.JPG</D:href><D:propstat><D:prop><D:resourcetype/><D:getcontentlength>6000000</D:getcontentlength></D:prop></D:propstat></D:response>
          <D:response><D:href>/remote.php/dav/files/me/Photos/a.png</D:href><D:propstat><D:prop><D:resourcetype/><D:getcontentlength>1</D:getcontentlength></D:prop></D:propstat></D:response>
          <D:response><D:href>/remote.php/dav/files/me/Photos/b.heic</D:href><D:propstat><D:prop><D:resourcetype/><D:getcontentlength>2</D:getcontentlength></D:prop></D:propstat></D:response>
          <D:response><D:href>/remote.php/dav/files/me/Photos/c.txt</D:href><D:propstat><D:prop><D:resourcetype/><D:getcontentlength>3</D:getcontentlength></D:prop></D:propstat></D:response>
        </D:multistatus>
        """
        let entries = PropfindParser.entries(PropfindParser.parse(Data(xml.utf8)), inFolder: "/remote.php/dav/files/me/Photos/")
        #expect(entries.filter(\.isDirectory).map(\.name) == ["2025", "Tràng An", "Old"])
        #expect(entries.filter { !$0.isDirectory }.map(\.name) == ["IMG 1.CR3", "Ảnh.JPG", "a.png", "b.heic", "c.txt"])
        #expect(entries.first { $0.name == "IMG 1.CR3" }?.size == 31_900_000)
        #expect(entries.first { $0.name == "IMG 1.CR3" }?.modified == Date(timeIntervalSince1970: 1_790_416_800))
    }

    @Test func moveRefusesToOverwrite() async throws {
        let dav = client()
        try await dav.createDirectory("A")
        StubWebDAVProtocol.lock.withLock {
            StubWebDAVProtocol.files["A/x.part"] = Data([1])
            StubWebDAVProtocol.files["A/x"] = Data([2])
        }
        await #expect(throws: RemoteFileError.self) { try await dav.move("A/x.part", to: "A/x") }
        #expect(try await dav.fileSize(at: "A/x") == 1)
        #expect(try await dav.directoryExists("A"))
        #expect(try await !dav.directoryExists("B"))
    }

    @Test func certificateFingerprintIsOpenSSLHex() {
        #expect(TLSCertificateTrust.fingerprint(ofCertificate: Data("abc".utf8))
            == "SHA-256 BA:78:16:BF:8F:01:CF:EA:41:41:40:DE:5D:AE:22:23:B0:03:61:A3:96:17:7A:9C:B4:10:FF:61:F2:00:15:AD")
    }
}
