import SwiftUI
import UIKit

/// A movie open in the player, with its engine's view.
struct PlayingMovie: Identifiable {
    let model: MoviePlayerModel
    let view: UIView
    var id: String { model.movie.id }
}

/// How a movie is opened for the player or for the movie page's panel
/// (FS-23.02 §1, FS-23.08 §4) — shared by the Movies grid and the page so
/// both build the same model.
@MainActor
struct MoviePlayback {
    let dependencies: AppDependencies

    var opener: MoviePlaybackOpener {
        MoviePlaybackOpener(store: dependencies.movies, servers: dependencies.fileServers, files: dependencies.movieDownloads.files)
    }

    /// Play: from the file on the device, else streamed from its source
    /// (AC-3). `fromStart` plays from 0:00 (FS-23.08 §3).
    func open(_ movie: Movie, fromStart: Bool = false) async throws -> PlayingMovie {
        var movie = movie
        if fromStart { movie.positionMs = 0 }
        switch try await opener.open(movie) {
        case .file(let url):
            let engine = VLCMoviePlayer(input: .file(url))
            let model = model(movie, engine: engine, loader: loader(), embedded: embeddedSubtitles(movie, isLocal: true, url: url) { try FileByteSource(url: url) })
            return PlayingMovie(model: model, view: engine.view)
        case .stream(let stream, let fileName, let close):
            let engine = VLCMoviePlayer(input: .stream(stream, fileName: fileName))
            let model = model(movie, engine: engine, loader: loader(stream), embedded: embeddedSubtitles(movie, isLocal: false, url: nil) { stream }) {
                Task { await close() }
            }
            return PlayingMovie(model: model, view: engine.view)
        }
    }

    func loader(_ stream: RemoteMovieStream? = nil) -> MovieSubtitleLoader {
        guard let stream else { return MovieSubtitleLoader(files: dependencies.movieDownloads.files) }
        return MovieSubtitleLoader(files: dependencies.movieDownloads.files) { try await stream.fetchFile($0) }
    }

    /// Subtitles inside the file (FS-23.03 §3): read off the device, or by
    /// Cues over the stream.
    func embeddedSubtitles(
        _ movie: Movie, isLocal: Bool, url: URL?, source: @escaping @Sendable () throws -> any MovieByteSource
    ) -> EmbeddedSubtitles {
        let extractor = EmbeddedSubtitleExtractor(store: dependencies.movies, files: dependencies.movieDownloads.files)
        return { listed in
            guard let bytes = try? source() else { return [] }
            return await extractor.extract(movie: movie, source: bytes, isLocal: isLocal, localURL: url, listed: listed)
        }
    }

    func model(
        _ movie: Movie, engine: any MoviePlaying, loader: MovieSubtitleLoader,
        embedded: EmbeddedSubtitles? = nil, onClose: @escaping () -> Void = {}
    ) -> MoviePlayerModel {
        MoviePlayerModel(
            movie: movie,
            player: engine,
            store: dependencies.movies,
            audioLanguages: MovieLanguagesScreen.current(.audio),
            subtitleLanguages: MovieLanguagesScreen.current(.subtitles),
            subtitleLoader: loader,
            defaultSubtitleStyle: MovieSubtitleStyle.decode(UserDefaults.standard.string(forKey: SettingsKeys.movieSubtitleStyle) ?? "{}"),
            rememberStyle: { UserDefaults.standard.set($0.json, forKey: SettingsKeys.movieSubtitleStyle) },
            sourceIsFiles: sourceIsFiles(movie),
            embeddedSubtitles: embedded,
            subtitleImporter: { [store = dependencies.movies, files = dependencies.movieDownloads.files] urls in
                try SubtitleImporter(store: store, files: files).importFiles(urls, into: movie.id, origin: .imported)
            },
            translations: dependencies.movieTranslations,
            translationService: TranslationService(providers: dependencies.aiProviders),
            onClose: onClose
        )
    }

    func sourceIsFiles(_ movie: Movie) -> Bool {
        guard let sourceId = movie.sourceId, let source = try? dependencies.movies.source(id: sourceId),
              let connectionId = source.connectionId else { return false }
        return (try? dependencies.fileServers.fetch(id: connectionId))??.transferProtocol == .files
    }
}
