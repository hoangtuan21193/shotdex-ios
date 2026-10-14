import Foundation
import Testing
@testable import ShotDex

/// FS-23.03 §3, AC-53, AC-55: text subtitles out of the movie file —
/// Matroska by Cues or by walking it, MP4 mov_text — checked against the
/// SRT and ASS the fixtures were made from (ffmpeg, mkvmerge with zlib).
@Suite @MainActor struct EmbeddedSubtitleExtractTests {
    static let folder = MoviePlayerFormatsTests.folder.appending(path: "subs")

    private func source(_ name: String) throws -> FileByteSource {
        try FileByteSource(url: Self.folder.appending(path: name))
    }

    private func original(_ name: String, _ format: SubtitleParser.Format) throws -> SubtitleDocument {
        SubtitleParser.parse(try String(contentsOf: Self.folder.appending(path: name), encoding: .utf8), format: format)
    }

    private func same(_ document: SubtitleDocument, _ expected: SubtitleDocument) {
        #expect(document.cues.count == expected.cues.count)
        for (got, want) in zip(document.cues, expected.cues) {
            #expect(abs(got.startMs - want.startMs) <= 10, "start \(got.startMs) vs \(want.startMs)")
            #expect(abs(got.endMs - want.endMs) <= 10, "end \(got.endMs) vs \(want.endMs)")
            #expect(got.lines == want.lines)
            #expect(got.placement == want.placement)
        }
    }

    /// ffmpeg's SRT track, by Cues: every line, its times and italics.
    @Test func srtByCues() async throws {
        let reader = MatroskaSubtitleReader(source: try source("ff.mkv"))
        let tracks = try await reader.readTracks()
        let text = try #require(tracks.first { $0.format == .srt })
        #expect(text.language == "eng")
        let result = try await reader.extract([text.number], walkWithoutCues: false)
        #expect(result.withoutCues.isEmpty)
        same(SubtitleParser.parse(try #require(result.texts[text.number]), format: .srt), try original("en.srt", .srt))
        // AC-53: the index, not the movie — a few kilobytes of a 230 KB file.
        #expect(reader.bytesRead < 40_000, "read \(reader.bytesRead) B")
    }

    /// mkvmerge, both tracks zlib-compressed: SRT and ASS (with `\an8` and
    /// italic) come out whole, by Cues and by walking alike.
    @Test func zlibSrtAndAss() async throws {
        for walk in [false, true] {
            let reader = MatroskaSubtitleReader(source: try source("mm-zlib.mkv"))
            let tracks = try await reader.readTracks()
            #expect(tracks.count == 2)
            let srt = try #require(tracks.first { $0.format == .srt })
            let ass = try #require(tracks.first { $0.format == .ass })
            #expect(MovieLanguage.code(ass.language) == "vi")
            let result: MatroskaSubtitleReader.Extraction
            if walk {
                // A walk is what the Cues-less fallback does on the device.
                result = try await reader.extract(Set(tracks.map(\.number)), walkWithoutCues: true)
            } else {
                result = try await reader.extract(Set(tracks.map(\.number)), walkWithoutCues: false)
            }
            same(SubtitleParser.parse(try #require(result.texts[srt.number]), format: .srt), try original("en.srt", .srt))
            let vi = SubtitleParser.parse(try #require(result.texts[ass.number]), format: .ass)
            same(vi, try original("vi.ass", .ass))
            #expect(vi.cues[3].placement == .top)
            #expect(vi.cues[4].lines.first?.first?.isItalic == true)
        }
    }

    /// AC-55: a track the Cues do not index is left to VLC when streamed,
    /// and walked for when the file is on the device.
    @Test func noCuesFallsBack() async throws {
        let streamed = MatroskaSubtitleReader(source: try source("nocues.mkv"))
        let tracks = try await streamed.readTracks()
        let number = try #require(tracks.first?.number)
        let remote = try await streamed.extract([number], walkWithoutCues: false)
        #expect(remote.withoutCues == [number])
        #expect(remote.texts.isEmpty)

        let local = MatroskaSubtitleReader(source: try source("nocues.mkv"))
        _ = try await local.readTracks()
        let walked = try await local.extract([number], walkWithoutCues: true)
        same(SubtitleParser.parse(try #require(walked.texts[number]), format: .srt), try original("en.srt", .srt))
    }

    /// AC-53 (stream): the same lines through a source stream, from a
    /// server; nothing is written to the device.
    @Test func streamedMovieExtractsInMemory() async throws {
        let data = try Data(contentsOf: Self.folder.appending(path: "mm-zlib.mkv"))
        let nas = InMemoryRemoteFileClient()
        nas.put("Movies/Film.mkv", data)
        let stream = RemoteMovieStream(client: nas, path: "Movies/Film.mkv", size: Int64(data.count))
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "embedded-\(UUID().uuidString)"))
        try files.prepare()
        let movie = Movie(sourceId: nil, title: "Film", originalFileName: "Film.mkv", byteCount: Int64(data.count), state: .stream, addedAt: 0)
        try store.add(movie)
        let found = await EmbeddedSubtitleExtractor(store: store, files: files).extract(movie: movie, source: stream, isLocal: false, localURL: nil)
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.document != nil && $0.subtitle.fileName.isEmpty && $0.subtitle.origin == .inFile })
        #expect(found.map(\.subtitle.language) == ["en", "vi"])
        #expect(!FileManager.default.fileExists(atPath: files.directory(for: movie.id).path))
        #expect(try store.subtitles(movieId: movie.id).count == 2)
    }

    /// On the device the text is written once; the next open reads no
    /// subtitle block again and keeps the same rows.
    @Test func downloadedMovieKeepsTheText() async throws {
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "embedded-\(UUID().uuidString)"))
        try files.prepare()
        let movie = Movie(sourceId: nil, title: "Film", originalFileName: "Film.mkv", byteCount: 1, state: .onDevice, addedAt: 0)
        try store.add(movie)
        let extractor = EmbeddedSubtitleExtractor(store: store, files: files)
        let url = Self.folder.appending(path: "ff.mkv")
        let first = await extractor.extract(movie: movie, source: try FileByteSource(url: url), isLocal: true, localURL: url)
        let row = try #require(first.first?.subtitle)
        #expect(!row.fileName.isEmpty)
        let again = await extractor.extract(movie: movie, source: try FileByteSource(url: url), isLocal: true, localURL: url)
        #expect(again.first?.subtitle.id == row.id)
        #expect(again.first?.document?.cues.count == 20)
        #expect(try store.subtitles(movieId: movie.id).count == 1)
    }

    /// MP4 mov_text through AVFoundation.
    @Test func movTextFromMP4() async throws {
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "embedded-\(UUID().uuidString)"))
        try files.prepare()
        let movie = Movie(sourceId: nil, title: "Clip", originalFileName: "movtext.mp4", byteCount: 1, state: .onDevice, addedAt: 0)
        try store.add(movie)
        let url = Self.folder.appending(path: "movtext.mp4")
        let found = await EmbeddedSubtitleExtractor(store: store, files: files).extract(movie: movie, source: try FileByteSource(url: url), isLocal: true, localURL: url)
        let document = try #require(found.first?.document)
        #expect(found.first?.subtitle.language == "en")
        #expect(document.cues.count == 20)
        #expect(document.cues.first?.startMs == 500)
        #expect(document.cues[1].plainText == "Line 2")
    }

    private func streamedModel(_ fixture: String) throws -> (MoviePlayerModel, FakeMoviePlayer, MovieStore) {
        let data = try Data(contentsOf: Self.folder.appending(path: fixture))
        let nas = InMemoryRemoteFileClient()
        nas.put("Movies/Film.mkv", data)
        let stream = RemoteMovieStream(client: nas, path: "Movies/Film.mkv", size: Int64(data.count))
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "embedded-\(UUID().uuidString)"))
        try files.prepare()
        let movie = Movie(sourceId: nil, title: "Film", originalFileName: "Film.mkv", byteCount: Int64(data.count), state: .stream, addedAt: 0)
        try store.add(movie)
        let extractor = EmbeddedSubtitleExtractor(store: store, files: files)
        let engine = FakeMoviePlayer()
        let model = MoviePlayerModel(
            movie: movie, player: engine, store: store, subtitleLanguages: ["en"],
            subtitleLoader: MovieSubtitleLoader(files: files),
            embeddedSubtitles: { listed in await extractor.extract(movie: movie, source: stream, isLocal: false, localURL: nil, listed: listed) }
        )
        return (model, engine, store)
    }

    /// AC-53 (model): a streamed movie's in-file English is chosen on a
    /// first open, drawn by ShotDex, and offered as Secondary too.
    @Test func streamedInFileIsPrimaryAndSecondary() async throws {
        let (model, engine, _) = try streamedModel("mm-zlib.mkv")
        await model.loadSubtitles()
        let english = try #require(model.subtitles.first { $0.language == "en" })
        #expect(model.subtitleChoice.primaryId == english.id)
        #expect(model.subtitleTitle(english) == "English · In File")
        #expect(model.primaryTimeline?.cues(atMs: 1_000).first?.lines.first?.first?.text == "Line 1")
        #expect(model.subtitles.allSatisfy(model.hasText))
        #expect(engine.embeddedSubtitleIndex == nil)
    }

    /// AC-55: without Cues the streamed track is VLC's to draw — Primary
    /// only, with the label that says why.
    @Test func streamedWithoutCuesGoesToVLC() async throws {
        let (model, engine, _) = try streamedModel("nocues.mkv")
        await model.loadSubtitles()
        let english = try #require(model.subtitles.first)
        #expect(!model.hasText(english))
        #expect(model.subtitleTitle(english) == "English · In File (Download to use as Secondary or translate)")
        #expect(model.subtitleChoice.primaryId == english.id)
        #expect(model.primaryTimeline == nil)
        #expect(engine.embeddedSubtitleIndex == 0)
        await model.selectSubtitle(nil, for: .primary)
        #expect(engine.embeddedSubtitleIndex == nil)
    }

    /// A home network answers each read in tens of milliseconds and a long
    /// movie has a thousand lines: the blocks the Cues name are fetched
    /// several at a time, and the text is the same as one by one.
    @Test func cueBlocksFetchedInParallel() async throws {
        let slow = SlowSource(inner: try source("mm-zlib.mkv"), delay: .milliseconds(15), width: 8)
        let reader = MatroskaSubtitleReader(source: slow)
        let tracks = try await reader.readTracks()
        let result = try await reader.extract(Set(tracks.map(\.number)), walkWithoutCues: false)
        let srt = try #require(tracks.first { $0.format == .srt })
        same(SubtitleParser.parse(try #require(result.texts[srt.number]), format: .srt), try original("en.srt", .srt))
        #expect(slow.mostInFlight > 1)
        #expect(slow.mostInFlight <= 8)
    }

    /// The tracks reach the menus as soon as the header is read — before
    /// their text, which VLC draws until it arrives.
    @Test func tracksListedBeforeTheirText() async throws {
        let data = try Data(contentsOf: Self.folder.appending(path: "mm-zlib.mkv"))
        let nas = InMemoryRemoteFileClient()
        nas.put("Movies/Film.mkv", data)
        let stream = RemoteMovieStream(client: nas, path: "Movies/Film.mkv", size: Int64(data.count))
        let store = MovieStore(database: try AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "embedded-\(UUID().uuidString)"))
        let movie = Movie(sourceId: nil, title: "Film", originalFileName: "Film.mkv", byteCount: Int64(data.count), state: .stream, addedAt: 0)
        try store.add(movie)
        let early = Box<[EmbeddedSubtitleExtractor.Found]>([])

        let found = await EmbeddedSubtitleExtractor(store: store, files: files)
            .extract(movie: movie, source: stream, isLocal: false, localURL: nil) { early.value = $0 }

        #expect(early.value.count == 2)
        #expect(early.value.allSatisfy { $0.isReading && $0.document == nil })
        #expect(found.allSatisfy { !$0.isReading && $0.document != nil })
        #expect(early.value.map(\.subtitle.id) == found.map(\.subtitle.id))
    }

    /// While the text is read the track says so, and VLC draws it.
    @Test func readingTrackIsDrawnByVLC() async throws {
        let (model, engine, _) = try streamedModel("mm-zlib.mkv")
        let english = Box<String?>(nil)
        model.onEmbeddedListed = {
            english.value = model.subtitles.first { $0.language == "en" }.map(model.subtitleTitle)
            #expect(engine.embeddedSubtitleIndex != nil)
        }
        await model.loadSubtitles()
        #expect(english.value == "English · In File (Reading…)")
        #expect(engine.embeddedSubtitleIndex == nil)
    }
}

private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// A source that answers after `delay` and counts reads in flight.
private final class SlowSource: MovieByteSource, @unchecked Sendable {
    let inner: FileByteSource
    let delay: Duration
    let width: Int
    private let lock = NSLock()
    private var inFlight = 0
    private(set) var mostInFlight = 0

    init(inner: FileByteSource, delay: Duration, width: Int) {
        self.inner = inner
        self.delay = delay
        self.width = width
    }

    var size: Int64 { inner.size }
    var concurrentReads: Int { width }

    func read(offset: Int64, length: Int) async throws -> Data {
        lock.withLock {
            inFlight += 1
            mostInFlight = max(mostInFlight, inFlight)
        }
        try await Task.sleep(for: delay)
        defer { lock.withLock { inFlight -= 1 } }
        return try await inner.read(offset: offset, length: length)
    }
}
