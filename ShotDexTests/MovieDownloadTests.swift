import Foundation
import Testing
@testable import ShotDex

/// FS-23.01 §6: Download to iPhone — queue, space check, resume, sweep.
@Suite(.serialized) @MainActor struct MovieDownloadTests {
    private struct Fixture {
        let store: MovieStore
        let files: MovieFileStore
        let nas: InMemoryRemoteFileClient
        let source: MovieSource
        let runner: MovieDownloadRunner
    }

    private func makeFixture(free: Int64 = 100_000_000_000, files: MovieFileStore? = nil, store: MovieStore? = nil, nas: InMemoryRemoteFileClient? = nil) throws -> Fixture {
        let store = try store ?? MovieStore(database: AppDatabase.makeEmpty(), plexTokens: InMemoryPasswordStore())
        let files = files ?? MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "movies-\(UUID().uuidString)"))
        let nas = nas ?? InMemoryRemoteFileClient()
        let source = (try store.sources().first) ?? MovieSource(kind: .folder, name: "NAS Home", folder: "Movies")
        try store.saveSource(source)
        let runner = MovieDownloadRunner(store: store, files: files, environment: .init(
            client: { _ in nas }, freeSpace: { free }, saveInterval: .milliseconds(1)
        ))
        return Fixture(store: store, files: files, nas: nas, source: source, runner: runner)
    }

    private func movie(_ f: Fixture, _ name: String) throws -> Movie {
        try #require(try f.store.movies().first { $0.originalFileName == name })
    }

    private static func bytes(_ n: Int) -> Data { Data((0..<n).map { UInt8(truncatingIfNeeded: $0 &* 7) }) }

    /// AC-4: the file lands in Movies/<id>/ at the right size, its subtitle
    /// comes along, and On This iPhone shows only it.
    @Test func downloadMarksOnDevice() async throws {
        let f = try makeFixture()
        f.nas.put("Movies/Dune.Part.Two.2024.mkv", Self.bytes(9_000_000))
        f.nas.put("Movies/Dune.Part.Two.2024.en.srt", Data("1\n00:00:01,000 --> 00:00:02,000\nhi\n".utf8))
        f.nas.put("Movies/Perfect.Days.2023.mkv", Self.bytes(10))
        try await MovieSourceSync.scan(f.source, client: f.nas, store: f.store)
        let dune = try movie(f, "Dune.Part.Two.2024.mkv")

        f.runner.download(dune.id)
        await f.runner.waitUntilIdle()

        let after = try #require(try f.store.movie(id: dune.id))
        #expect(after.state == .onDevice)
        #expect(after.downloadError == nil)
        let file = try #require(f.files.file(for: after))
        #expect(file.path.hasPrefix(f.files.directory(for: dune.id).path))
        #expect(try Data(contentsOf: file) == Self.bytes(9_000_000))
        let subtitle = try #require(try f.store.subtitles(movieId: dune.id).first)
        #expect(!subtitle.fileName.isEmpty)
        #expect(FileManager.default.fileExists(atPath: f.files.directory(for: dune.id).appending(path: subtitle.fileName).path))
        #expect(MovieLibraryQuery(filter: .onDevice).apply(try f.store.movies()).map(\.id) == [dune.id])
        #expect(!FileManager.default.fileExists(atPath: f.files.partFile(for: dune.id).path))
    }

    /// AC-7: 3.5 GB free, 3.2 GB movie: refused with the shortfall, not a
    /// byte read, and the queue stops.
    @Test func needsSizePlusOneGB() async throws {
        let f = try makeFixture(free: 3_500_000_000)
        let big = Movie(sourceId: f.source.id, remotePath: "Movies/Big.mkv", title: "Big", originalFileName: "Big.mkv", byteCount: 3_200_000_000, state: .stream)
        let small = Movie(sourceId: f.source.id, remotePath: "Movies/Small.mkv", title: "Small", originalFileName: "Small.mkv", byteCount: 10, state: .stream)
        try f.store.add(big)
        try f.store.add(small)
        f.nas.put("Movies/Small.mkv", Self.bytes(10))

        f.runner.download(big.id)
        f.runner.download(small.id)
        await f.runner.waitUntilIdle()

        let refused = try #require(try f.store.movie(id: big.id))
        #expect(refused.state == .stream)
        #expect(refused.downloadError == "Not enough space on this device — about 0.7 GB needed.")
        #expect(f.nas.bytesRead == 0)
        #expect(try f.store.movie(id: small.id)?.state == .queued)
    }

    /// AC-8: the server goes away at 4 MB of 10 MB — red line; back, Retry:
    /// carries on from the bytes on disk, never reading the file twice.
    @Test func resumesFromBytesOnDisk() async throws {
        let f = try makeFixture()
        f.nas.put("Movies/Heat.mkv", Self.bytes(10_000_000))
        try await MovieSourceSync.scan(f.source, client: f.nas, store: f.store)
        let heat = try movie(f, "Heat.mkv")
        f.nas.failRangeReadsAfter = 1

        f.runner.download(heat.id)
        await f.runner.waitUntilIdle()

        let paused = try #require(try f.store.movie(id: heat.id))
        #expect(paused.downloadError == "Download paused — NAS Home unreachable")
        #expect(paused.downloadedBytes == Int64(ResumableFile.chunkSize))

        f.nas.failRangeReadsAfter = nil
        f.runner.retry(heat.id)
        await f.runner.waitUntilIdle()

        #expect(try f.store.movie(id: heat.id)?.state == .onDevice)
        #expect(f.nas.bytesRead <= 10_000_000 + 1_048_576)
        let heatFile = try #require(f.files.file(for: try movie(f, "Heat.mkv")))
        #expect(try Data(contentsOf: heatFile) == Self.bytes(10_000_000))
    }

    /// AC-9: the app was killed mid-download; at launch it carries on from
    /// the part, and a part no movie owns is swept.
    @Test func resumesAfterKill() async throws {
        let first = try makeFixture()
        first.nas.put("Movies/Arrival.mkv", Self.bytes(6_000_000))
        try await MovieSourceSync.scan(first.source, client: first.nas, store: first.store)
        let arrival = try movie(first, "Arrival.mkv")
        try first.files.prepare()
        try Self.bytes(6_000_000).prefix(2_500_000).write(to: first.files.partFile(for: arrival.id))
        try Data([1, 2, 3]).write(to: first.files.partFile(for: "orphan"))
        try first.store.setState(id: arrival.id, .downloading, downloadedBytes: 2_500_000)

        // A new launch: same database and folders, a fresh runner.
        let relaunch = try makeFixture(files: first.files, store: first.store, nas: first.nas)
        await relaunch.runner.resumeInterrupted().value
        await relaunch.runner.waitUntilIdle()

        #expect(try relaunch.store.movie(id: arrival.id)?.state == .onDevice)
        #expect(first.nas.bytesRead == 3_500_000)
        #expect(!FileManager.default.fileExists(atPath: first.files.partFile(for: "orphan").path))
    }

    /// AC-10 (folder half): Movies/ is out of iCloud backup.
    @Test func excludedFromBackup() throws {
        let files = MovieFileStore(root: FileManager.default.temporaryDirectory.appending(path: "movies-\(UUID().uuidString)"))
        try files.prepare()
        #expect(files.isExcludedFromBackup)
    }

    /// A downloaded movie whose file vanished is marked Missing at launch,
    /// not deleted (FS-23.05 §1).
    @Test func sweepMarksMissing() async throws {
        let f = try makeFixture()
        f.nas.put("Movies/Up.mkv", Self.bytes(100))
        try await MovieSourceSync.scan(f.source, client: f.nas, store: f.store)
        let up = try movie(f, "Up.mkv")
        f.runner.download(up.id)
        await f.runner.waitUntilIdle()
        try FileManager.default.removeItem(at: f.files.directory(for: up.id))

        await f.runner.resumeInterrupted().value

        #expect(try f.store.movie(id: up.id)?.state == .missing)
    }

    /// AC-11: Dune downloaded, watched to 47:12, one translation: Remove
    /// Download frees the file, keeps the place and the translation.
    @Test func removeDownloadKeepsProgress() async throws {
        let f = try makeFixture()
        f.nas.put("Movies/Dune.mkv", Self.bytes(3_000_000))
        f.nas.put("Movies/Dune.en.srt", Data("1\n00:00:01,000 --> 00:00:02,000\nhi\n".utf8))
        try await MovieSourceSync.scan(f.source, client: f.nas, store: f.store)
        let dune = try movie(f, "Dune.mkv")
        f.runner.download(dune.id)
        await f.runner.waitUntilIdle()
        try f.store.recordPosition(id: dune.id, positionMs: 2_832_000)
        let english = try #require(try f.store.subtitles(movieId: dune.id).first)
        let translated = try f.files.write(Data("vi".utf8), named: "vi-translated.srt", for: dune.id)
        try f.store.saveSubtitle(MovieSubtitle(movieId: dune.id, language: "vi", origin: .translated, translatedFromId: english.id, format: .srt, fileName: translated))
        let downloaded = try #require(try f.store.movie(id: dune.id))
        let file = try #require(f.files.file(for: downloaded))

        f.runner.removeDownload(downloaded)

        #expect(!FileManager.default.fileExists(atPath: file.path))
        let after = try #require(try f.store.movie(id: dune.id))
        #expect(after.state == .stream)
        #expect(after.positionMs == 2_832_000)
        #expect(after.localFileName == nil)
        let subtitles = try f.store.subtitles(movieId: dune.id)
        #expect(subtitles.first { $0.origin == .sidecar }?.fileName == "")
        #expect(subtitles.contains { $0.origin == .translated })
        #expect(FileManager.default.fileExists(atPath: f.files.directory(for: dune.id).appending(path: translated).path))
        #expect(f.nas.files["Movies/Dune.mkv"] != nil)
    }

    /// Download to iPhone on a Plex movie shows as waiting before its
    /// server answers; Cancel on the version question puts it back.
    @Test func preparingShowsAtOnce() throws {
        let f = try makeFixture()
        let heat = Movie(sourceId: f.source.id, remotePath: "Movies/Heat.mkv", title: "Heat", originalFileName: "Heat.mkv", byteCount: 10, state: .stream)
        try f.store.add(heat)
        let before = f.runner.revision

        f.runner.prepare(heat.id)

        #expect(try f.store.movie(id: heat.id)?.state == .queued)
        #expect(f.runner.revision > before)
        #expect(MovieLibraryQuery(filter: .onDevice).apply(try f.store.movies()).map(\.id) == [heat.id])

        f.runner.cancelPreparing(heat.id)

        #expect(try f.store.movie(id: heat.id)?.state == .stream)
    }

    /// A late progress report never undoes a finished download.
    @Test func progressOnlyWhileDownloading() throws {
        let f = try makeFixture()
        let heat = Movie(sourceId: f.source.id, remotePath: "Movies/Heat.mkv", title: "Heat", originalFileName: "Heat.mkv", byteCount: 10, state: .downloading)
        try f.store.add(heat)

        try f.store.setDownloadProgress(id: heat.id, bytes: 4)
        #expect(try f.store.movie(id: heat.id)?.downloadedBytes == 4)

        try f.store.setState(id: heat.id, .onDevice, downloadedBytes: 10)
        try f.store.setDownloadProgress(id: heat.id, bytes: 6)
        #expect(try f.store.movie(id: heat.id)?.downloadedBytes == 10)
    }
}
