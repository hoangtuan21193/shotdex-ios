import Foundation

/// Before a Plex movie downloads (FS-23.07 §3): its versions, sharpest
/// first, and its separate subtitle files, so they come along.
struct PlexDownloadPreparer: Sendable {
    let store: MovieStore
    var client = PlexClient()

    func versions(of movie: Movie) async throws -> [PlexClient.Version] {
        guard let key = movie.plexRatingKey, let sourceId = movie.sourceId,
              let source = try store.source(id: sourceId), let token = store.plexToken(for: sourceId),
              let base = try await PlexLibrarySync(store: store, client: client).baseURL(for: source, token: token) else { return [] }
        let item = try await client.item(server: base, token: token, ratingKey: key)
        var seen = Set<String>()
        let subtitles = item.subtitles.filter { $0.key.map { seen.insert($0).inserted } ?? false }.map {
            ScannedSubtitle(remotePath: $0.key ?? "", language: MovieLanguage.code($0.languageCode),
                            format: MovieSubtitle.Format(rawValue: $0.codec ?? "srt") ?? .srt, origin: .plex)
        }
        try? store.syncPlexSubtitles(movieId: movie.id, subtitles)
        return item.versions
    }

    func choose(_ version: PlexClient.Version, for movie: Movie) throws {
        try store.setPlexVersion(id: movie.id, partKey: version.partKey, byteCount: version.size)
    }
}
