import Foundation
import Testing
@testable import ShotDex

/// A Plex server and plex.tv in one closure (FS-23.07 tests): what the app
/// asks, and the JSON shapes spike S3 recorded.
final class PlexStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, headers, body) = Self.handler?(request) ?? (404, [:], Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func client() -> PlexClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlexStubProtocol.self]
        return PlexClient(session: URLSession(configuration: configuration), clientIdentifier: "test-device")
    }
}

@Suite(.serialized) @MainActor struct PlexTests {
    static let movieBytes = Data((0..<200_000).map { UInt8($0 % 251) })

    private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    /// A fake account: PIN K7Q2, two servers (one at home), one Movies
    /// library with Dune — two versions — and a Vietnamese .srt beside it.
    private func installFake(revoked: Bool = false) {
        PlexStubProtocol.requests = []
        PlexStubProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let token = request.value(forHTTPHeaderField: "X-Plex-Token")
            if Self.serverDown, request.url?.host == "plex.home" { return (503, [:], Data()) }
            if path == "/:/timeline" || path == "/:/scrobble" || path == "/:/unscrobble" { return (200, [:], Data()) }
            if revoked, token != nil { return (401, [:], Data()) }
            switch path {
            case "/api/v2/pins": return (201, [:], self.json(["id": 42, "code": "K7Q2", "expiresIn": 900]))
            case "/api/v2/pins/42": return (200, [:], self.json(["id": 42, "code": "K7Q2", "authToken": "account-token"]))
            case "/api/v2/resources":
                return (200, [:], self.json([
                    ["name": "Away Box", "provides": "server", "clientIdentifier": "far", "accessToken": "far-token", "owned": false,
                     "connections": [["uri": "https://far.example.com:32400", "local": false, "relay": false]]],
                    ["name": "Mac Studio", "provides": "server", "clientIdentifier": "home", "accessToken": "home-token", "owned": true,
                     "connections": [["uri": "http://plex.home:32400", "local": true, "relay": false]]],
                ]))
            case "/identity": return (200, [:], self.json(["MediaContainer": ["machineIdentifier": "home"]]))
            case "/library/sections":
                return (200, [:], self.json(["MediaContainer": ["Directory": [
                    ["key": "1", "title": "Movies", "type": "movie"], ["key": "9", "title": "Music", "type": "artist"],
                ]]]))
            case "/library/sections/1/all":
                return (200, [:], self.json(["MediaContainer": ["size": 1, "totalSize": 1, "Metadata": [Self.dune(withStreams: false)]]]))
            case "/library/metadata/101":
                return (200, [:], self.json(["MediaContainer": ["Metadata": [Self.dune(withStreams: true)]]]))
            case "/library/parts/4k/file.mkv", "/library/parts/hd/file.mkv":
                let range = request.value(forHTTPHeaderField: "Range") ?? ""
                let numbers = range.replacingOccurrences(of: "bytes=", with: "").split(separator: "-").compactMap { Int($0) }
                let total = Self.movieBytes.count
                let start = numbers.first ?? 0
                let end = min(total - 1, numbers.count > 1 ? numbers[1] : total - 1)
                return (206, ["Content-Range": "bytes \(start)-\(end)/\(total)"], Self.movieBytes.subdata(in: start..<(end + 1)))
            case "/library/streams/77":
                let srt = Data("1\n00:00:01,000 --> 00:00:02,000\nXin chào\n".utf8)
                return (206, ["Content-Range": "bytes 0-\(srt.count - 1)/\(srt.count)"], srt)
            default: return (404, [:], Data())
            }
        }
    }

    /// Downloads need the listed size to be the bytes served.
    nonisolated(unsafe) static var servedSizes = false
    /// Where Dune stands on the server, and when it was last watched there.
    nonisolated(unsafe) static var serverProgress: (offset: Int, viewedAt: Int)?
    nonisolated(unsafe) static var serverDown = false

    static func dune(withStreams: Bool) -> [String: Any] {
        func part(_ key: String, size: Int64) -> [String: Any] {
            var part: [String: Any] = ["key": key, "size": servedSizes ? Int64(movieBytes.count) : size, "container": "mkv", "file": "/media/Dune.Part.Two.2024.mkv"]
            if withStreams {
                part["Stream"] = [["streamType": 3, "key": "/library/streams/77", "languageCode": "vie", "codec": "srt"]]
            }
            return part
        }
        return [
            "ratingKey": "101", "type": "movie", "title": "Dune: Part Two", "year": 2024,
            "summary": "Paul Atreides unites with the Fremen.", "duration": 9_960_000, "thumb": "/library/metadata/101/thumb/1",
            "Genre": [["tag": "Science Fiction"], ["tag": "Adventure"]],
            "viewOffset": serverProgress?.offset ?? 0, "lastViewedAt": serverProgress?.viewedAt as Any, "viewCount": 0,
            "Media": [
                ["height": 1080, "videoResolution": "1080", "Part": [part("/library/parts/hd/file.mkv", size: 8_100_000_000)]],
                ["height": 2160, "videoResolution": "4k", "Part": [part("/library/parts/4k/file.mkv", size: 54_300_000_000)]],
            ],
        ]
    }

    private func store() throws -> MovieStore {
        MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
    }

    /// AC-47 (logic): the code, the token, servers with the home one first,
    /// and Add bringing Dune in with Plex's year and poster; the token only
    /// in the Keychain store.
    @Test func pinFlow() async throws {
        installFake()
        let client = PlexStubProtocol.client()
        let pin = try await client.createPin()
        #expect(pin.code == "K7Q2")
        let token = try #require(try await client.token(for: pin))
        let servers = try await client.servers(accountToken: token)
        #expect(servers.map(\.name) == ["Mac Studio", "Away Box"])
        #expect(servers[0].isOnThisNetwork)
        let address = try #require(await client.fastestConnection(servers[0]))
        #expect(address.absoluteString == "http://plex.home:32400")
        #expect(try await client.libraries(server: address, token: servers[0].accessToken).map(\.title) == ["Movies"])

        let movies = try store()
        let source = MovieSource(kind: .plex, name: "Mac Studio", plexMachineId: "home", plexAddress: address.absoluteString)
        try movies.saveSource(source, plexToken: servers[0].accessToken)
        await PlexLibrarySync(store: movies, client: client).refresh(source)
        let dune = try #require(try movies.movies().first)
        #expect(dune.title == "Dune: Part Two")
        #expect(dune.year == 2024)
        #expect(dune.plexRatingKey == "101")
        #expect(dune.byteCount == 54_300_000_000)
        #expect(dune.posterPath?.hasPrefix("/photo/:/transcode?width=480&height=720") == true)
        #expect(dune.genres == "Science Fiction, Adventure")
        #expect(movies.plexToken(for: source.id) == "home-token")
        let rows = try movies.sources()
        #expect(!String(describing: rows).contains("home-token"))
        #expect(PlexStubProtocol.requests.allSatisfy { $0.url?.query?.contains("X-Plex-Token") != true })
    }

    /// AC-51: a revoked token dims the source and asks for a new sign-in;
    /// nothing is removed.
    @Test func revokedToken() async throws {
        installFake()
        let client = PlexStubProtocol.client()
        let movies = try store()
        let source = MovieSource(kind: .plex, name: "Mac Studio", plexMachineId: "home", plexAddress: "http://plex.home:32400")
        try movies.saveSource(source, plexToken: "home-token")
        await PlexLibrarySync(store: movies, client: client).refresh(source)
        #expect(try movies.movies().count == 1)

        installFake(revoked: true)
        await PlexLibrarySync(store: movies, client: client).refresh(source)
        let after = try #require(try movies.source(id: source.id))
        #expect(after.needsSignIn)
        #expect(!after.isReachable)
        #expect(try movies.movies().count == 1)
    }

    /// AC-48, AC-56: Play streams the 4K original by Range with the token in
    /// a header — no transcode request — and the Vietnamese .srt shows up
    /// as `From Plex`.
    @Test func directPlay() async throws {
        installFake()
        let client = PlexStubProtocol.client()
        let movies = try store()
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "plex-\(UUID().uuidString)"))
        try files.prepare()
        let source = MovieSource(kind: .plex, name: "Mac Studio", plexMachineId: "home", plexAddress: "http://plex.home:32400")
        try movies.saveSource(source, plexToken: "home-token")
        await PlexLibrarySync(store: movies, client: client).refresh(source)
        let dune = try #require(try movies.movies().first)

        var opener = MoviePlaybackOpener(store: movies, servers: FileServerStore(database: try AppDatabase.makeEmpty(), passwords: InMemoryPasswordStore()), files: files)
        opener.plexClient = client
        guard case .stream(let stream, let fileName, _) = try await opener.open(dune) else {
            Issue.record("expected a stream")
            return
        }
        #expect(fileName == "Dune.Part.Two.2024.mkv")
        #expect(stream.size == 54_300_000_000)
        stream.open()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let read = await Task.detached { stream.read(&buffer, maxLength: 4_096) }.value
        #expect(read == 4_096)
        let partRequests = PlexStubProtocol.requests.filter { $0.url?.path.hasPrefix("/library/parts/") == true }
        #expect(partRequests.allSatisfy { $0.url?.path == "/library/parts/4k/file.mkv" })
        #expect(partRequests.allSatisfy { $0.value(forHTTPHeaderField: "X-Plex-Token") == "home-token" && $0.value(forHTTPHeaderField: "Range") != nil })
        #expect(!PlexStubProtocol.requests.contains { $0.url?.path.contains("transcode") == true && $0.url?.path.contains("photo") == false })

        let subtitle = try #require(try movies.subtitles(movieId: dune.id).first)
        #expect(subtitle.origin == .plex)
        #expect(MovieSubtitleLabel.title(subtitle) == "Tiếng Việt · From Plex")
        let text = try await stream.fetchFile(try #require(subtitle.remotePath))
        #expect(String(decoding: text, as: UTF8.self).contains("Xin chào"))
    }

    /// AC-56: versions sharpest first, labelled as the Download list shows.
    @Test func versions() throws {
        let item = try #require(PlexClient.item(Self.dune(withStreams: false)))
        #expect(item.versions.map(\.label) == ["4K · \(Int64(54_300_000_000).formatted(.byteCount(style: .file)))", "1080p · \(Int64(8_100_000_000).formatted(.byteCount(style: .file)))"])
        #expect(item.versions.first?.partKey == "/library/parts/4k/file.mkv")
    }

    /// AC-49, AC-56: Download offers the versions, takes only the one
    /// picked, and the movie keeps Plex's year, summary, genres and its
    /// subtitle file on the device.
    @Test func downloadChosenVersionWithMetadata() async throws {
        Self.servedSizes = true
        defer { Self.servedSizes = false }
        installFake()
        let client = PlexStubProtocol.client()
        let movies = try store()
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "plex-dl-\(UUID().uuidString)"))
        try files.prepare()
        let source = MovieSource(kind: .plex, name: "Mac Studio", plexMachineId: "home", plexAddress: "http://plex.home:32400")
        try movies.saveSource(source, plexToken: "home-token")
        await PlexLibrarySync(store: movies, client: client).refresh(source)
        let dune = try #require(try movies.movies().first)

        let preparer = PlexDownloadPreparer(store: movies, client: client)
        let versions = try await preparer.versions(of: dune)
        #expect(versions.count == 2)
        let hd = try #require(versions.last)
        try preparer.choose(hd, for: dune)

        let runner = MovieDownloadRunner(store: movies, files: files, environment: .init(
            client: { _ in PlexFileClient(base: URL(string: "http://plex.home:32400")!, token: "home-token", session: client.session, client: client) },
            freeSpace: { .max }
        ))
        PlexStubProtocol.requests = []
        runner.download(dune.id)
        await runner.waitUntilIdle()

        let saved = try #require(try movies.movie(id: dune.id))
        #expect(saved.state == .onDevice)
        #expect(saved.year == 2024)
        #expect(saved.summary == "Paul Atreides unites with the Fremen.")
        #expect(saved.genres == "Science Fiction, Adventure")
        let file = try #require(files.file(for: saved))
        #expect(try Data(contentsOf: file) == Self.movieBytes)
        let parts = PlexStubProtocol.requests.compactMap(\.url?.path).filter { $0.hasPrefix("/library/parts/") }
        #expect(!parts.isEmpty && parts.allSatisfy { $0 == "/library/parts/hd/file.mkv" })
        let subtitle = try #require(try movies.subtitles(movieId: dune.id).first { $0.origin == .plex })
        #expect(!subtitle.fileName.isEmpty)
    }

    /// AC-50: 30:00 watched on the TV opens here at 30:00; 52:10 watched
    /// here offline goes up the first time the server answers again.
    @Test func twoWayAndOfflineQueue() async throws {
        let now = Int(Date().timeIntervalSince1970)
        Self.serverProgress = (1_800_000, now - 60)
        defer { Self.serverProgress = nil; Self.serverDown = false }
        installFake()
        let client = PlexStubProtocol.client()
        let movies = try store()
        let source = MovieSource(kind: .plex, name: "Mac Studio", plexMachineId: "home", plexAddress: "http://plex.home:32400")
        try movies.saveSource(source, plexToken: "home-token")
        let sync = PlexLibrarySync(store: movies, client: client)
        await sync.refresh(source)
        var dune = try #require(try movies.movies().first)
        #expect(dune.positionMs == 1_800_000)
        #expect(MoviePlaybackPosition.resumeMs(saved: dune.positionMs, durationMs: dune.durationMs ?? 0) == 1_800_000)

        // On the plane: the server is gone, the place is recorded here.
        Self.serverDown = true
        try movies.recordPosition(id: dune.id, positionMs: 3_130_000, at: Date())
        await sync.refresh(try #require(try movies.source(id: source.id)))
        dune = try #require(try movies.movie(id: dune.id))
        #expect(dune.plexSyncPending)
        #expect(dune.positionMs == 3_130_000)

        // Home again: 52:10 goes up, and the server's older 30:00 does not
        // come back down over it.
        Self.serverDown = false
        PlexStubProtocol.requests = []
        await sync.refresh(try #require(try movies.source(id: source.id)))
        let timeline = try #require(PlexStubProtocol.requests.first { $0.url?.path == "/:/timeline" })
        #expect(timeline.url?.query?.contains("time=3130000") == true)
        #expect(timeline.url?.query?.contains("X-Plex-Token") != true)
        dune = try #require(try movies.movie(id: dune.id))
        #expect(!dune.plexSyncPending)
        #expect(dune.positionMs == 3_130_000)
    }
}
