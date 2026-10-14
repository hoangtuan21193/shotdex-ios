import Foundation

/// A Plex source's movies (FS-23.07 §1–2): reach the server by the way that
/// answered last, else race them all again; list the chosen libraries a page
/// at a time; merge like a folder rescan. A refused token marks the source
/// `Sign in to Plex again` and dims its streamed movies (AC-51); downloads
/// still play.
struct PlexLibrarySync: Sendable {
    let store: MovieStore
    var client = PlexClient()

    /// Where the server answers now, remembered for next time.
    func baseURL(for source: MovieSource, token: String) async throws -> URL? {
        if let remembered = source.plexAddress.flatMap(URL.init(string:)) {
            var request = URLRequest(url: remembered.appending(path: "identity"))
            request.timeoutInterval = 3
            client.authorize(&request, token: token)
            if let (_, response) = try? await client.session.data(for: request) {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 { throw PlexClient.Failure.signedOut }
                if (200..<300).contains(status) { return remembered }
            }
        }
        let servers = try await client.servers(accountToken: token)
        guard let server = servers.first(where: { $0.machineId == source.plexMachineId }),
              let fastest = await client.fastestConnection(server) else { return nil }
        try? store.setPlexAddress(fastest.absoluteString, sourceId: source.id)
        return fastest
    }

    @discardableResult
    func refresh(_ source: MovieSource) async -> MovieStore.ScanMerge {
        guard source.kind == .plex else { return MovieStore.ScanMerge() }
        guard let token = store.plexToken(for: source.id) else {
            try? store.setNeedsSignIn(true, sourceId: source.id)
            try? store.setReachable(false, sourceId: source.id)
            return MovieStore.ScanMerge()
        }
        do {
            guard let base = try await baseURL(for: source, token: token) else {
                try? store.setReachable(false, sourceId: source.id)
                return MovieStore.ScanMerge()
            }
            // What was watched here while away goes up first (§4).
            await pushProgress(source: source, base: base, token: token)
            let chosen = Set((try? JSONDecoder().decode([String].self, from: Data(source.plexLibraries.utf8))) ?? [])
            let libraries = try await client.libraries(server: base, token: token).filter { chosen.isEmpty || chosen.contains($0.key) }
            var items: [PlexClient.Item] = []
            for library in libraries {
                items += try await client.items(server: base, token: token, library: library)
            }
            let found = items.compactMap(Self.scanned)
            try? store.setNeedsSignIn(false, sourceId: source.id)
            try? store.setReachable(true, sourceId: source.id)
            let merge = (try? store.mergeScan(sourceId: source.id, found: found, isComplete: true)) ?? MovieStore.ScanMerge()
            // …then what was watched elsewhere comes down.
            try? store.applyPlexProgress(sourceId: source.id, items.map {
                ($0.ratingKey, $0.viewOffsetMs ?? 0, $0.viewCount > 0 && ($0.viewOffsetMs ?? 0) == 0, $0.lastViewedAt)
            })
            return merge
        } catch PlexClient.Failure.signedOut {
            try? store.setNeedsSignIn(true, sourceId: source.id)
            try? store.setReachable(false, sourceId: source.id)
        } catch {
            try? store.setReachable(false, sourceId: source.id)
        }
        return MovieStore.ScanMerge()
    }

    /// One Plex item as a scanned movie: the sharpest version's file and
    /// size, Plex's own title, year, summary, genres and poster.
    static func scanned(_ item: PlexClient.Item) -> ScannedMovie? {
        guard let best = item.versions.first else { return nil }
        return ScannedMovie(
            plexRatingKey: item.ratingKey,
            title: item.title, year: item.year, season: item.season, episode: item.episode,
            originalFileName: (best.file as NSString).lastPathComponent.isEmpty
                ? "\(item.title).\(best.container ?? "mkv")" : (best.file as NSString).lastPathComponent,
            byteCount: best.size, durationMs: item.durationMs, summary: item.summary,
            genres: item.genres.isEmpty ? nil : item.genres.joined(separator: ", "),
            posterPath: item.thumb.map(PlexClient.posterPath)
        )
    }

    /// Positions and watched marks recorded on this device that Plex has
    /// not heard yet — offline viewing included (AC-50). A mark that fails
    /// to send stays owed.
    func pushProgress(source: MovieSource, base: URL, token: String) async {
        guard let owed = try? store.pendingPlexSync(sourceId: source.id), !owed.isEmpty else { return }
        var sent: [Movie] = []
        for movie in owed {
            guard let key = movie.plexRatingKey else { continue }
            do {
                if movie.isWatched {
                    try await client.setWatched(true, server: base, token: token, ratingKey: key)
                } else if movie.positionMs == 0 {
                    // Marked unwatched here.
                    try await client.setWatched(false, server: base, token: token, ratingKey: key)
                } else {
                    try await client.reportPosition(server: base, token: token, ratingKey: key, timeMs: movie.positionMs, durationMs: movie.durationMs ?? 0)
                }
                sent.append(movie)
            } catch {
                continue
            }
        }
        try? store.markPlexSynced(sent)
    }
}
