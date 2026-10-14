import Foundation
import Testing
@testable import ShotDex

/// FS-23.03 §5: subtitles the user brings — files, zips, Share.
@Suite @MainActor struct SubtitleImportTests {
    static let folder = EmbeddedSubtitleExtractTests.folder

    private struct Fixture {
        let store: MovieStore
        let files: MovieFileStore
        let movie: Movie
        var importer: SubtitleImporter { SubtitleImporter(store: store, files: files) }
    }

    private func fixture() throws -> Fixture {
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "import-\(UUID().uuidString)"))
        try files.prepare()
        let movie = Movie(sourceId: nil, title: "Dune Part Two", year: 2024, originalFileName: "Dune.Part.Two.2024.mkv", byteCount: 1, state: .onDevice, addedAt: 0)
        try store.add(movie)
        return Fixture(store: store, files: files, movie: movie)
    }

    /// AC-26: a zip gives its two subtitles, EN and VI; the readme stays
    /// out. A zip of text alone says so.
    @Test func zipTakesSubtitlesOnly() throws {
        let f = try fixture()
        let result = try f.importer.importFiles([Self.folder.appending(path: "subs.zip")], into: f.movie.id, origin: .imported)
        #expect(result.added.count == 2)
        #expect(Set(result.added.compactMap(\.language)) == ["en", "vi"])
        #expect(Set(result.added.map(\.format)) == [.srt, .ass])
        let saved = try f.store.subtitles(movieId: f.movie.id)
        #expect(saved.count == 2)
        for subtitle in saved {
            #expect(FileManager.default.fileExists(atPath: f.files.directory(for: f.movie.id).appending(path: subtitle.fileName).path))
        }
        #expect(throws: SubtitleImporter.Failure.noSubtitles) {
            try f.importer.importFiles([Self.folder.appending(path: "only-text.zip")], into: f.movie.id, origin: .imported)
        }
    }

    /// The same text twice is added once; something that is not a
    /// subtitle adds nothing.
    @Test func duplicatesAndUnreadable() throws {
        let f = try fixture()
        let first = try f.importer.importFiles([Self.folder.appending(path: "en.srt")], into: f.movie.id, origin: .imported)
        #expect(first.added.count == 1)
        let again = try f.importer.importFiles([Self.folder.appending(path: "subs.zip")], into: f.movie.id, origin: .imported)
        #expect(again.added.count == 1)
        #expect(again.duplicates == 1)

        let junk = FileManager.default.temporaryDirectory.appending(path: "junk-\(UUID().uuidString).srt")
        try Data("not a subtitle at all".utf8).write(to: junk)
        #expect(throws: SubtitleImporter.Failure.unreadable) {
            try f.importer.importFiles([junk], into: f.movie.id, origin: .imported)
        }
        #expect(try f.store.subtitles(movieId: f.movie.id).count == 2)
    }

    /// A subtitle with no language in its name gets one from its words.
    @Test func languageFromNameElseText() throws {
        let f = try fixture()
        let unnamed = FileManager.default.temporaryDirectory.appending(path: "track-\(UUID().uuidString).srt")
        let text = (1...12).map { "\($0)\n00:00:\(String(format: "%02d", $0)),000 --> 00:00:\(String(format: "%02d", $0)),900\nChúng ta phải đi ngay bây giờ, trước khi cơn bão tới đây và cuốn trôi mọi thứ.\n" }.joined(separator: "\n")
        try Data(text.utf8).write(to: unnamed)
        let result = try f.importer.importFiles([unnamed], into: f.movie.id, origin: .shared)
        #expect(result.added.first?.language == "vi")
        #expect(result.added.first?.origin == .shared)
        #expect(SubtitleFileName.language("Dune.Part.Two.2024.English.forced.srt") == "en")
        #expect(SubtitleFileName.language("Dune.vie.srt") == "vi")
        #expect(SubtitleFileName.language("Dune.srt") == nil)
    }

    /// AC-25 (logic): the movie a shared file is named after is found
    /// among others.
    @Test func sharedFileFindsItsMovie() {
        let dune = Movie(sourceId: nil, title: "Dune", year: 2024, originalFileName: "Dune.2024.mkv", byteCount: 1, state: .onDevice, addedAt: 0)
        let others = ["Heat", "Arrival", "Past Lives"].map { Movie(sourceId: nil, title: $0, originalFileName: "\($0).mkv", byteCount: 1, state: .onDevice, addedAt: 0) }
        #expect(SubtitleFileName.matchingMovie("Dune.vi.srt", in: others + [dune])?.id == dune.id)
        #expect(SubtitleFileName.matchingMovie("Dune.2024.1080p.vi.srt", in: others + [dune])?.id == dune.id)
        #expect(SubtitleFileName.matchingMovie("Dune.1984.vi.srt", in: others + [dune]) == nil)
        #expect(SubtitleFileName.matchingMovie("Interstellar.en.srt", in: others + [dune]) == nil)
    }

    /// Import File… from the Secondary menu: the files join the movie and
    /// the first new one becomes the Secondary; a bad file says why.
    @Test func importFileFromThePanel() async throws {
        let f = try fixture()
        let importer = f.importer
        let movieId = f.movie.id
        let model = MoviePlayerModel(
            movie: f.movie, player: FakeMoviePlayer(), store: f.store,
            subtitleLoader: MovieSubtitleLoader(files: f.files),
            subtitleImporter: { try importer.importFiles($0, into: movieId, origin: .imported) }
        )
        await model.loadSubtitles()
        await model.importSubtitles([Self.folder.appending(path: "subs.zip")])
        #expect(model.subtitles.count == 2)
        let secondary = try #require(model.subtitle(id: model.subtitleChoice.secondaryId))
        #expect(secondary.origin == .imported)
        #expect(model.secondaryTimeline != nil)
        #expect(model.subtitleTitle(secondary).hasSuffix("· Imported"))

        await model.importSubtitles([Self.folder.appending(path: "only-text.zip")])
        #expect(model.subtitleImportFailure == "No subtitles in this file.")
    }
}
