import Foundation
import Testing
@testable import ShotDex

/// FS-23.01 §2, AC-6: Add Movie Files…, Share and AirDrop copy into
/// Movies; the original stays.
@Suite @MainActor struct MovieImportTests {
    private func fixture() throws -> (MovieStore, MovieFileStore, URL) {
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "movies-\(UUID().uuidString)"))
        let picked = FileManager.default.temporaryDirectory.appending(path: "picked-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        return (store, files, picked)
    }

    /// AC-6: clip.flv (with its subtitle) and clip.webm are copied, marked
    /// on the device; the files picked are untouched.
    @Test func addFilesCopies() throws {
        let (store, files, picked) = try fixture()
        let flv = picked.appending(path: "clip.flv")
        let srt = picked.appending(path: "clip.en.srt")
        let webm = picked.appending(path: "Holiday.2023.webm")
        try Data(repeating: 3, count: 300_000).write(to: flv)
        try Data("1\n00:00:01,000 --> 00:00:02,000\nhi\n".utf8).write(to: srt)
        try Data(repeating: 9, count: 200_000).write(to: webm)

        let result = try MovieImporter(store: store, files: files).importFiles([flv, srt, webm])

        #expect(result.movieIds.count == 2)
        #expect(result.ignored.isEmpty)
        let movies = try store.movies()
        #expect(movies.allSatisfy { $0.isOnDevice && $0.sourceId == nil && $0.fileHash != nil })
        #expect(Set(movies.map(\.displayTitle)) == ["clip", "Holiday"])
        let clip = try #require(movies.first { $0.originalFileName == "clip.flv" })
        let copied = try #require(files.file(for: clip))
        #expect(try Data(contentsOf: copied) == Data(repeating: 3, count: 300_000))
        #expect(FileManager.default.fileExists(atPath: flv.path))
        let subtitle = try #require(try store.subtitles(movieId: clip.id).first)
        #expect(subtitle.language == "en")
        #expect(FileManager.default.fileExists(atPath: files.directory(for: clip.id).appending(path: subtitle.fileName).path))
        #expect(MovieLibraryQuery(filter: .onDevice).apply(movies).count == 2)
    }

    /// The same file again is recognised by its movie hash, not copied twice.
    @Test func duplicateIsNotCopiedTwice() throws {
        let (store, files, picked) = try fixture()
        let movie = picked.appending(path: "Dune.mkv")
        try Data(repeating: 5, count: 150_000).write(to: movie)
        let importer = MovieImporter(store: store, files: files)
        let first = try importer.importFiles([movie])

        let again = try importer.importFiles([movie])

        #expect(again.skippedDuplicates == 1)
        #expect(again.movieIds == first.movieIds)
        #expect(try store.movies().count == 1)
    }

    @Test func otherFilesAreIgnored() throws {
        let (store, files, picked) = try fixture()
        let pdf = picked.appending(path: "notes.pdf")
        try Data("x".utf8).write(to: pdf)
        let result = try MovieImporter(store: store, files: files).importFiles([pdf])
        #expect(result.movieIds.isEmpty)
        #expect(result.ignored == ["notes.pdf"])
    }
}
