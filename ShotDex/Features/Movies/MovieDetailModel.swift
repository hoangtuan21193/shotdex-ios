import Foundation
import Observation

/// Navigation value for the movie page (FS-23.08 §1).
struct MovieDetailDestination: Hashable {
    let movieId: String
}

/// The movie page (FS-23.08): the row, live; Plex's versions; and an
/// Audio & Subtitles panel on a stand-in player, so choices made here are
/// the ones the movie opens with.
@MainActor
@Observable
final class MovieDetailModel {
    private(set) var movie: Movie
    /// Plex: every version, sharpest first (empty for a folder movie).
    private(set) var versions: [PlexClient.Version] = []
    /// The panel's model; nil until the source was asked (or could not be).
    private(set) var tracks: MoviePlayerModel?
    private let probe: MovieProbePlayer
    private let playback: MoviePlayback
    @ObservationIgnored private var close: (@Sendable () async -> Void)?
    @ObservationIgnored private var hasLoaded = false

    init(movie: Movie, playback: MoviePlayback) {
        self.movie = movie
        self.playback = playback
        probe = MovieProbePlayer(durationMs: movie.durationMs ?? 0)
    }

    var store: MovieStore { playback.dependencies.movies }

    /// The row again, after a download, a rename or a choice.
    func reload() {
        if let fresh = try? store.movie(id: movie.id) { movie = fresh }
    }

    /// Opens the source once: Plex's versions, the audio tracks, the
    /// subtitles inside the file. Offline it stops at what is stored.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        if movie.plexRatingKey != nil {
            versions = (try? await PlexDownloadPreparer(store: store).versions(of: movie)) ?? []
        }
        var audio = chosenVersion?.audioTracks
        if audio?.isEmpty == true { audio = nil }
        let model: MoviePlayerModel
        switch try? await playback.opener.open(movie) {
        case .file(let url)?:
            if audio == nil, let source = try? FileByteSource(url: url) {
                audio = await MovieTrackProbe.audioTracks(fileName: url.lastPathComponent, source: source, localURL: url)
            }
            model = playback.model(movie, engine: probe, loader: playback.loader(),
                                   embedded: playback.embeddedSubtitles(movie, isLocal: true, url: url) { try FileByteSource(url: url) })
        case .stream(let stream, let fileName, let close)?:
            self.close = close
            if audio == nil { audio = await MovieTrackProbe.audioTracks(fileName: fileName, source: stream, localURL: nil) }
            model = playback.model(movie, engine: probe, loader: playback.loader(stream),
                                   embedded: playback.embeddedSubtitles(movie, isLocal: false, url: nil) { stream })
        case nil:
            model = playback.model(movie, engine: probe, loader: playback.loader())
        }
        probe.setAudioTracks(audio)
        tracks = model
        await model.loadSubtitles()
    }

    /// The page went away: the connection goes too.
    func unload() {
        let close = close
        self.close = nil
        if let close { Task { await close() } }
    }

    // MARK: What the page says

    /// The version Play and Download use (FS-23.08 §4).
    var chosenVersion: PlexClient.Version? {
        versions.first { $0.partKey == movie.plexPartKey } ?? versions.first
    }

    func choose(_ version: PlexClient.Version) {
        try? PlexDownloadPreparer(store: store).choose(version, for: movie)
        reload()
    }

    /// `English · TrueHD 7.1`; `Chosen when playing` before the tracks are known.
    var audioSummary: String {
        guard let tracks, probe.knowsTracks, !tracks.audioTracks.isEmpty else {
            return String(localized: "Chosen when playing", comment: "Movie page: the audio track is picked once the movie opens")
        }
        let chosen = tracks.audioTracks.first { $0.id == tracks.selectedAudioTrackId } ?? tracks.audioTracks[0]
        let position = (tracks.audioTracks.firstIndex(of: chosen) ?? 0) + 1
        return [MovieAudioTrackLabel.title(chosen, position: position), MovieAudioTrackLabel.detail(chosen)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// `Tiếng Việt + English`, or `Off`.
    var subtitleSummary: String {
        guard let tracks else { return String(localized: "Off", comment: "Movie page: no subtitles chosen") }
        let names = [tracks.subtitleChoice.primaryId, tracks.subtitleChoice.secondaryId]
            .compactMap { tracks.subtitle(id: $0) }
            .map(MovieSubtitleLabel.language)
        return names.isEmpty ? String(localized: "Off", comment: "Movie page: no subtitles chosen") : names.joined(separator: " + ")
    }

    /// Where to start: 47:12 of a movie watched part way; nil = from the start.
    var resumeMs: Int64? {
        MoviePlaybackPosition.resumeMs(saved: movie.positionMs, durationMs: movie.durationMs ?? 0)
    }

    /// `2024 · 2:46:00 · 4K`.
    var facts: String {
        var parts: [String] = []
        if let caption = MovieRowText.yearOrEpisode(movie) { parts.append(caption) }
        if let duration = MovieRowText.duration(movie) { parts.append(duration) }
        if let quality = chosenVersion?.label.components(separatedBy: " · ").first, quality != "—" { parts.append(quality) }
        return parts.joined(separator: " · ")
    }

    /// `Mac Studio · 6.1 GB`.
    var whereFrom: String {
        let size = movie.byteCount.formatted(.byteCount(style: .file))
        return [movie.isOnDevice ? MoviesCountText.onDeviceShort() : movie.sourceName, size].compactMap { $0 }.joined(separator: " · ")
    }
}
