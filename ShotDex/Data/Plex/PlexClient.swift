import Foundation

/// Plex's public API (FS-23.07, spike S3): sign-in by PIN, the account's
/// servers, libraries a page at a time, one movie's details, and the watch
/// position. The token always travels in a header, never in a URL.
struct PlexClient: Sendable {
    var session: URLSession = .shared
    var plexTV = PlexClient.debugPlexTV ?? URL(string: "https://plex.tv")!
    var clientsPlexTV = PlexClient.debugPlexTV ?? URL(string: "https://clients.plex.tv")!
    /// One per install; plex.tv lists the device under it.
    var clientIdentifier: String = PlexClient.installIdentifier
    var deviceName = "ShotDex"

    /// DEBUG only: a stand-in plex.tv on this Mac for simulator runs
    /// (`defaults write … plex.debugPlexTV http://127.0.0.1:32401`).
    static var debugPlexTV: URL? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "plex.debugPlexTV").flatMap(URL.init(string:))
        #else
        nil
        #endif
    }

    static var installIdentifier: String {
        let key = "plex.clientIdentifier"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    enum Failure: Error, Equatable {
        /// 401: the token was revoked or the password changed (AC-51).
        case signedOut
        case unreachable
        case badResponse
        case notFound
    }

    // MARK: Sign in (§1)

    struct Pin: Equatable, Sendable {
        var id: Int
        var code: String
        var expiresAt: Date
    }

    func createPin() async throws -> Pin {
        var request = URLRequest(url: plexTV.appending(path: "api/v2/pins").appending(queryItems: [URLQueryItem(name: "strong", value: "false")]))
        request.httpMethod = "POST"
        let object = try await json(request, token: nil)
        guard let id = object["id"] as? Int, let code = object["code"] as? String else { throw Failure.badResponse }
        let expiresIn = (object["expiresIn"] as? Double) ?? 900
        return Pin(id: id, code: code, expiresAt: Date().addingTimeInterval(expiresIn))
    }

    /// The account token once the code was entered at plex.tv/link.
    func token(for pin: Pin) async throws -> String? {
        let object = try await json(URLRequest(url: plexTV.appending(path: "api/v2/pins/\(pin.id)")), token: nil)
        return (object["authToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Servers (§1–2)

    struct Server: Equatable, Sendable, Identifiable {
        var id: String { machineId }
        var machineId: String
        var name: String
        /// The server's own token: a shared server has one of its own.
        var accessToken: String
        var connections: [Connection]
        var owned: Bool

        /// plex.tv calls a connection local; the list puts those first.
        var isOnThisNetwork: Bool { connections.contains { $0.local && !$0.relay } }
    }

    struct Connection: Equatable, Sendable {
        var uri: URL
        var local: Bool
        var relay: Bool
    }

    func servers(accountToken: String) async throws -> [Server] {
        let url = clientsPlexTV.appending(path: "api/v2/resources").appending(queryItems: [
            URLQueryItem(name: "includeHttps", value: "1"), URLQueryItem(name: "includeRelay", value: "1"),
        ])
        let data = try await send(URLRequest(url: url), token: accountToken)
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw Failure.badResponse }
        return list.compactMap { item in
            guard (item["provides"] as? String)?.contains("server") == true,
                  let machine = item["clientIdentifier"] as? String, let name = item["name"] as? String else { return nil }
            let connections = (item["connections"] as? [[String: Any]] ?? []).compactMap { connection -> Connection? in
                guard let uri = (connection["uri"] as? String).flatMap(URL.init(string:)) else { return nil }
                return Connection(uri: uri, local: connection["local"] as? Bool ?? false, relay: connection["relay"] as? Bool ?? false)
            }
            return Server(
                machineId: machine, name: name, accessToken: item["accessToken"] as? String ?? accountToken,
                connections: connections, owned: item["owned"] as? Bool ?? false
            )
        }
        .sorted { $0.isOnThisNetwork && !$1.isOnThisNetwork }
    }

    /// Every way in at once, the network's own first and the relay last;
    /// the first to answer wins (S3: plex.tv lists dead ones as local, and
    /// `publicAddressMatches` is wrong at home). `remembered` is tried
    /// alongside them.
    func fastestConnection(_ server: Server, remembered: URL? = nil, timeout: TimeInterval = 3) async -> URL? {
        var candidates = server.connections.sorted { lhs, rhs in
            (lhs.local ? 0 : lhs.relay ? 2 : 1) < (rhs.local ? 0 : rhs.relay ? 2 : 1)
        }.map(\.uri)
        if let remembered {
            candidates.removeAll { $0 == remembered }
            candidates.insert(remembered, at: 0)
        }
        return await withTaskGroup(of: URL?.self) { group in
            for (index, uri) in candidates.enumerated() {
                group.addTask {
                    // Later (relay) ones start a little after, so a quick
                    // local answer wins without racing them all.
                    if index > 0 { try? await Task.sleep(for: .milliseconds(min(index, 4) * 150)) }
                    var request = URLRequest(url: uri.appending(path: "identity"))
                    request.timeoutInterval = timeout
                    return (try? await self.send(request, token: server.accessToken)) == nil ? nil : uri
                }
            }
            for await winner in group {
                if let winner {
                    group.cancelAll()
                    return winner
                }
            }
            return nil
        }
    }

    // MARK: Libraries (§1, S3 §3)

    struct Library: Equatable, Sendable, Identifiable {
        var id: String { key }
        var key: String
        var title: String
        /// `movie` or `show`.
        var type: String
    }

    func libraries(server: URL, token: String) async throws -> [Library] {
        let object = try await json(URLRequest(url: server.appending(path: "library/sections")), token: token)
        let directories = ((object["MediaContainer"] as? [String: Any])?["Directory"] as? [[String: Any]]) ?? []
        return directories.compactMap { item in
            guard let key = item["key"] as? String, let title = item["title"] as? String, let type = item["type"] as? String,
                  type == "movie" || type == "show" else { return nil }
            return Library(key: key, title: title, type: type)
        }
    }

    struct Item: Equatable, Sendable {
        var ratingKey: String
        var title: String
        var year: Int?
        var season: Int?
        var episode: Int?
        var summary: String?
        var genres: [String]
        var durationMs: Int64?
        var thumb: String?
        var viewOffsetMs: Int64?
        var viewCount: Int
        var lastViewedAt: Int?
        var versions: [Version]
        var subtitles: [Subtitle]
    }

    /// One `Media` of an item: a copy at one quality.
    struct Version: Equatable, Sendable {
        var height: Int?
        var resolution: String?
        var size: Int64
        var container: String?
        var partKey: String
        var file: String

        /// `4K · 54.3 GB`, `1080p · 8.1 GB`.
        var label: String {
            let quality: String = switch resolution?.lowercased() {
            case "4k"?: "4K"
            case let value? where Int(value) != nil: "\(value)p"
            case let value?: value.uppercased()
            case nil: height.map { "\($0)p" } ?? "—"
            }
            return "\(quality) · \(size.formatted(.byteCount(style: .file)))"
        }
    }

    /// A subtitle stream; `key` is set for a separate file on the server.
    struct Subtitle: Equatable, Sendable {
        var key: String?
        var languageCode: String?
        var codec: String?
    }

    /// Movies or episodes of a library, `pageSize` at a time.
    func items(server: URL, token: String, library: Library, pageSize: Int = 200) async throws -> [Item] {
        var all: [Item] = []
        var start = 0
        while true {
            let url = server.appending(path: "library/sections/\(library.key)/all").appending(queryItems: [
                URLQueryItem(name: "type", value: library.type == "show" ? "4" : "1"),
                URLQueryItem(name: "X-Plex-Container-Start", value: String(start)),
                URLQueryItem(name: "X-Plex-Container-Size", value: String(pageSize)),
            ])
            let object = try await json(URLRequest(url: url), token: token)
            let container = object["MediaContainer"] as? [String: Any] ?? [:]
            let page = (container["Metadata"] as? [[String: Any]] ?? []).compactMap(Self.item)
            all += page
            let total = container["totalSize"] as? Int ?? container["size"] as? Int ?? all.count
            start += pageSize
            if page.count < pageSize || all.count >= total { break }
        }
        return all
    }

    func item(server: URL, token: String, ratingKey: String) async throws -> Item {
        let object = try await json(URLRequest(url: server.appending(path: "library/metadata/\(ratingKey)")), token: token)
        guard let first = ((object["MediaContainer"] as? [String: Any])?["Metadata"] as? [[String: Any]])?.first,
              let item = Self.item(first) else { throw Failure.notFound }
        return item
    }

    static func item(_ json: [String: Any]) -> Item? {
        guard let ratingKey = json["ratingKey"] as? String else { return nil }
        let isEpisode = json["type"] as? String == "episode"
        let media = json["Media"] as? [[String: Any]] ?? []
        let versions = media.compactMap { medium -> Version? in
            guard let part = (medium["Part"] as? [[String: Any]])?.first, let key = part["key"] as? String else { return nil }
            return Version(
                height: medium["height"] as? Int, resolution: (medium["videoResolution"] as? String),
                size: (part["size"] as? NSNumber)?.int64Value ?? 0, container: part["container"] as? String,
                partKey: key, file: part["file"] as? String ?? ""
            )
        }
        .sorted { ($0.height ?? 0, $0.size) > ($1.height ?? 0, $1.size) }
        let streams = media.flatMap { ($0["Part"] as? [[String: Any]] ?? []).flatMap { $0["Stream"] as? [[String: Any]] ?? [] } }
        let subtitles = streams.filter { ($0["streamType"] as? Int) == 3 }.map {
            Subtitle(key: $0["key"] as? String, languageCode: $0["languageCode"] as? String, codec: $0["codec"] as? String)
        }
        return Item(
            ratingKey: ratingKey,
            title: isEpisode ? (json["grandparentTitle"] as? String ?? json["title"] as? String ?? "") : (json["title"] as? String ?? ""),
            year: json["year"] as? Int,
            season: isEpisode ? json["parentIndex"] as? Int : nil,
            episode: isEpisode ? json["index"] as? Int : nil,
            summary: json["summary"] as? String,
            genres: (json["Genre"] as? [[String: Any]] ?? []).compactMap { $0["tag"] as? String },
            durationMs: (json["duration"] as? NSNumber)?.int64Value,
            thumb: json["thumb"] as? String,
            viewOffsetMs: (json["viewOffset"] as? NSNumber)?.int64Value,
            viewCount: json["viewCount"] as? Int ?? 0,
            lastViewedAt: json["lastViewedAt"] as? Int,
            versions: versions, subtitles: subtitles
        )
    }

    /// The poster Grid shows: 480×720 from Plex's transcoder (S3: 64 KB
    /// against 1.1 MB for the original).
    static func posterPath(_ thumb: String) -> String {
        var components = URLComponents()
        components.path = "/photo/:/transcode"
        components.queryItems = [
            URLQueryItem(name: "width", value: "480"), URLQueryItem(name: "height", value: "720"),
            URLQueryItem(name: "url", value: thumb),
        ]
        return components.string ?? thumb
    }

    // MARK: Watch position (§4)

    func reportPosition(server: URL, token: String, ratingKey: String, timeMs: Int64, durationMs: Int64) async throws {
        let url = server.appending(path: ":/timeline").appending(queryItems: [
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "key", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "state", value: "stopped"),
            URLQueryItem(name: "time", value: String(timeMs)),
            URLQueryItem(name: "duration", value: String(durationMs)),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
        ])
        _ = try await send(URLRequest(url: url), token: token)
    }

    func setWatched(_ watched: Bool, server: URL, token: String, ratingKey: String) async throws {
        let url = server.appending(path: watched ? ":/scrobble" : ":/unscrobble").appending(queryItems: [
            URLQueryItem(name: "key", value: ratingKey),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
        ])
        _ = try await send(URLRequest(url: url), token: token)
    }

    // MARK: Requests

    /// The headers every Plex request carries, the token among them.
    func authorize(_ request: inout URLRequest, token: String?) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ShotDex", forHTTPHeaderField: "X-Plex-Product")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(deviceName, forHTTPHeaderField: "X-Plex-Device-Name")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Plex-Token") }
    }

    private func json(_ request: URLRequest, token: String?) async throws -> [String: Any] {
        let data = try await send(request, token: token)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.badResponse }
        return object
    }

    private func send(_ request: URLRequest, token: String?) async throws -> Data {
        var request = request
        if request.timeoutInterval > 30 { request.timeoutInterval = 15 }
        authorize(&request, token: token)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.badResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw Failure.signedOut
        case 404: throw Failure.notFound
        default: throw Failure.badResponse
        }
    }
}
