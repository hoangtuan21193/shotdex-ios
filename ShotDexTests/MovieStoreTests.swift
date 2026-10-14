import Foundation
import GRDB
import Testing
@testable import ShotDex

/// The Movies tables (FS-23.05 §2): what a scan may rewrite, what the user
/// owns, and what goes with a source or a movie.
@Suite @MainActor struct MovieStoreTests {
    private struct Fixture {
        let database: AppDatabase
        let store: MovieStore
        let tokens: InMemoryPasswordStore
        let nas: FileServer
        let folder: MovieSource
    }

    private func makeFixture() throws -> Fixture {
        let database = try AppDatabase.makeEmpty()
        let servers = FileServerStore(database: database, passwords: InMemoryPasswordStore())
        let nas = FileServer(name: "NAS Home", transferProtocol: .smb, host: "192.168.1.20", username: "me", share: "Movies")
        try servers.save(nas, password: "secret")
        let tokens = InMemoryPasswordStore()
        let store = MovieStore(database: database, plexTokens: tokens)
        let folder = MovieSource(kind: .folder, name: "Movies on NAS Home", connectionId: nas.id, folder: "Films")
        try store.saveSource(folder)
        return Fixture(database: database, store: store, tokens: tokens, nas: nas, folder: folder)
    }

    private func file(_ name: String, size: Int64 = 1_000, year: Int? = nil) -> ScannedMovie {
        ScannedMovie(remotePath: "Films/\(name).mkv", title: name, year: year, originalFileName: "\(name).mkv", byteCount: size)
    }

    private func movie(_ f: Fixture, path: String) throws -> Movie {
        try #require(try f.store.movies().first { $0.remotePath == path })
    }

    /// A rescan rewrites the file facts and nothing the user did.
    @Test func rescanKeepsWhatTheUserDid() throws {
        let f = try makeFixture()
        let first = try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune"), file("Arrival")], isComplete: true)
        #expect(first == MovieStore.ScanMerge(added: 2))

        let dune = try movie(f, path: "Films/Dune.mkv")
        try f.store.rename(id: dune.id, to: "Dune: Part One")
        try f.store.recordPosition(id: dune.id, positionMs: 2_832_000)
        try f.store.setAudio(id: dune.id, trackId: "audio/2", delayMs: -120)
        try f.store.setPlaybackRate(1.25, id: dune.id)

        let second = try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune", size: 2_000, year: 2021), file("Arrival")], isComplete: true)
        #expect(second == MovieStore.ScanMerge(updated: 1))

        let after = try movie(f, path: "Films/Dune.mkv")
        #expect(after.id == dune.id)
        #expect(after.byteCount == 2_000)
        #expect(after.year == 2021)
        #expect(after.displayTitle == "Dune: Part One")
        #expect(after.positionMs == 2_832_000)
        #expect(after.audioTrackId == "audio/2")
        #expect(after.audioDelayMs == -120)
        #expect(after.playbackRate == 1.25)
        #expect(after.state == .stream)
        #expect(!after.plexSyncPending)
    }

    /// A file gone from the source: the streamed row is hidden, the
    /// downloaded one stays with a label; both come back whole.
    @Test func rescanHidesStreamedKeepsDownloaded() throws {
        let f = try makeFixture()
        try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune"), file("Arrival"), file("Heat")], isComplete: true)
        let arrival = try movie(f, path: "Films/Arrival.mkv")
        let heat = try movie(f, path: "Films/Heat.mkv")
        try f.store.setState(id: arrival.id, .onDevice, downloadedBytes: 1_000)
        try f.store.recordPosition(id: heat.id, positionMs: 600_000)

        let merge = try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune")], isComplete: true, at: Date(timeIntervalSince1970: 500))
        #expect(merge == MovieStore.ScanMerge(markedRemoved: 2))
        #expect(Set(try f.store.movies().map(\.originalFileName)) == ["Dune.mkv", "Arrival.mkv"])
        #expect(try f.store.movie(id: arrival.id)?.removedFromSourceAt == 500)
        #expect(try f.store.movie(id: heat.id)?.isHidden == true)

        // Back on the source: nothing was lost.
        try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune"), file("Arrival"), file("Heat")], isComplete: true)
        #expect(try f.store.movie(id: arrival.id)?.removedFromSourceAt == nil)
        #expect(try f.store.movie(id: heat.id)?.positionMs == 600_000)
        #expect(try f.store.movies().count == 3)
    }

    /// A NAS that answered with nothing, or a listing that did not finish,
    /// removes nothing — streamed rows keep their history.
    @Test func emptyOrPartialScanRemovesNothing() throws {
        let f = try makeFixture()
        try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune"), file("Arrival"), file("Heat")], isComplete: true)
        let dune = try movie(f, path: "Films/Dune.mkv")
        try f.store.rename(id: dune.id, to: "Dune: Part One")
        try f.store.recordPosition(id: dune.id, positionMs: 42_000)
        try f.store.saveSubtitle(MovieSubtitle(movieId: dune.id, language: "vi", origin: .imported, format: .srt, fileName: "vi.srt"))

        #expect(try f.store.mergeScan(sourceId: f.folder.id, found: [], isComplete: true) == MovieStore.ScanMerge())
        #expect(try f.store.mergeScan(sourceId: f.folder.id, found: [file("Heat")], isComplete: false) == MovieStore.ScanMerge())

        let after = try #require(try f.store.movie(id: dune.id))
        #expect(!after.isHidden)
        #expect(after.displayTitle == "Dune: Part One")
        #expect(after.positionMs == 42_000)
        #expect(try f.store.subtitles(movieId: dune.id).count == 1)
        #expect(try f.store.movies().count == 3)
    }

    /// Renamed or moved on the NAS: same name and size at a new path is the
    /// same movie, with its position and subtitles.
    @Test func movedOnSourceKeepsHistory() throws {
        let f = try makeFixture()
        try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune", size: 7_000)], isComplete: true)
        let dune = try movie(f, path: "Films/Dune.mkv")
        try f.store.recordPosition(id: dune.id, positionMs: 1_200_000)

        let moved = ScannedMovie(remotePath: "Films/Sci-Fi/Dune.mkv", title: "Dune", originalFileName: "Dune.mkv", byteCount: 7_000)
        let merge = try f.store.mergeScan(sourceId: f.folder.id, found: [moved], isComplete: true)

        #expect(merge == MovieStore.ScanMerge(adopted: 1))
        let after = try #require(try f.store.movie(id: dune.id))
        #expect(after.remotePath == "Films/Sci-Fi/Dune.mkv")
        #expect(after.positionMs == 1_200_000)
        #expect(try f.store.movies().count == 1)
    }

    /// A downloaded movie keeps the name and size of its own file when the
    /// source renames it.
    @Test func downloadedRowKeepsItsFileFacts() throws {
        let f = try makeFixture()
        let plex = MovieSource(kind: .plex, name: "Mac Studio", plexMachineId: "abc")
        try f.store.saveSource(plex)
        try f.store.mergeScan(sourceId: plex.id, found: [ScannedMovie(plexRatingKey: "13", title: "Dune", originalFileName: "Dune.mkv", byteCount: 9)], isComplete: true)
        let dune = try #require(try f.store.movies().first)
        try f.store.setState(id: dune.id, .onDevice, downloadedBytes: 9)
        try f.store.setLocalFileName("Dune.mkv", id: dune.id)

        try f.store.mergeScan(sourceId: plex.id, found: [ScannedMovie(plexRatingKey: "13", title: "Dune (2021)", year: 2021, originalFileName: "Dune.2021.2160p.mkv", byteCount: 50)], isComplete: true)

        let after = try #require(try f.store.movie(id: dune.id))
        #expect(after.title == "Dune (2021)")
        #expect(after.year == 2021)
        #expect(after.originalFileName == "Dune.mkv")
        #expect(after.localFileName == "Dune.mkv")
        #expect(after.byteCount == 9)
    }

    /// Two Plex items may point at the same file path (two libraries, two
    /// editions); they never clash and never fail the scan.
    @Test func plexItemsSharingAPathBothLand() throws {
        let f = try makeFixture()
        let plex = MovieSource(kind: .plex, name: "Mac Studio", plexMachineId: "abc")
        try f.store.saveSource(plex)
        let merge = try f.store.mergeScan(sourceId: plex.id, found: [
            ScannedMovie(remotePath: "/media/Dune.mkv", plexRatingKey: "13", title: "Dune", originalFileName: "Dune.mkv", byteCount: 9),
            ScannedMovie(remotePath: "/media/Dune.mkv", plexRatingKey: "77", title: "Dune", originalFileName: "Dune.mkv", byteCount: 9),
        ], isComplete: true)
        #expect(merge.added == 2)
        #expect(try f.store.movies().allSatisfy { $0.remotePath == nil && $0.plexMachineId == "abc" })
    }

    /// FS-23.01 §2: removing a source takes its streamed movies, keeps the
    /// downloaded ones (no source now), and removes its Plex token.
    @Test func removeSourceKeepsDownloads() throws {
        let f = try makeFixture()
        let plex = MovieSource(kind: .plex, name: "Mac Studio", plexMachineId: "abc", plexAddress: "https://192-168-1-2.x.plex.direct:32400")
        try f.store.saveSource(plex, plexToken: "plex-token")
        try f.store.mergeScan(sourceId: plex.id, found: [
            ScannedMovie(plexRatingKey: "13", title: "Dune", originalFileName: "Dune.mkv", byteCount: 9),
            ScannedMovie(plexRatingKey: "14", title: "Heat", originalFileName: "Heat.mkv", byteCount: 9),
        ], isComplete: true)
        let dune = try #require(try f.store.movies().first { $0.plexRatingKey == "13" })
        try f.store.setState(id: dune.id, .onDevice, downloadedBytes: 9, plexPartKey: "/library/parts/1/file.mkv")
        try f.store.recordPosition(id: dune.id, positionMs: 5_000)
        let heat = try #require(try f.store.movies().first { $0.plexRatingKey == "14" })
        try f.store.saveSubtitle(MovieSubtitle(movieId: heat.id, language: "vi", origin: .plex, format: .srt, fileName: "s.srt"))

        let removed = try f.store.removeSource(id: plex.id)

        #expect(removed == [heat.id])
        #expect(try f.store.source(id: plex.id) == nil)
        #expect(f.tokens.password(for: plex.id) == nil)
        let kept = try #require(try f.store.movie(id: dune.id))
        #expect(kept.sourceId == nil)
        #expect(kept.sourceName == "Mac Studio")
        #expect(kept.isOnDevice)
        #expect(kept.plexPartKey == "/library/parts/1/file.mkv")
        #expect(try f.store.subtitles(movieId: heat.id).isEmpty)

        // No source, no Plex to owe.
        try f.store.recordPosition(id: dune.id, positionMs: 9_000)
        #expect(try f.store.movie(id: dune.id)?.positionMs == 9_000)

        // The same server added again: the download rejoins it.
        let again = MovieSource(kind: .plex, name: "Mac Studio", plexMachineId: "abc")
        try f.store.saveSource(again)
        let merge = try f.store.mergeScan(sourceId: again.id, found: [ScannedMovie(plexRatingKey: "13", title: "Dune", originalFileName: "Dune.mkv", byteCount: 9)], isComplete: true)
        #expect(merge == MovieStore.ScanMerge(adopted: 1))
        #expect(try f.store.movie(id: dune.id)?.sourceId == again.id)
        #expect(try f.store.movies().count == 1)
    }

    /// Removing the FS-15 connection removes the folder source on it: its
    /// streamed movies go (nothing left to play them from), its downloaded
    /// movies stay.
    @Test func deletingConnectionRemovesFolderSource() throws {
        let f = try makeFixture()
        try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune"), file("Heat")], isComplete: true)
        let dune = try movie(f, path: "Films/Dune.mkv")
        try f.store.setState(id: dune.id, .onDevice)

        try FileServerStore(database: f.database, passwords: InMemoryPasswordStore()).delete(id: f.nas.id)

        #expect(try f.store.sources().isEmpty)
        #expect(try f.store.movies().map(\.id) == [dune.id])
        #expect(try f.store.movie(id: dune.id)?.sourceId == nil)
        let stranded = try f.database.reader.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM movies WHERE sourceId IS NULL AND state NOT IN ('onDevice', 'missing')")
        }
        #expect(stranded == 0)
    }

    /// Hidden streamed rows go for good after 30 days; downloads never do.
    @Test func purgeRemovedAfterThirtyDays() throws {
        let f = try makeFixture()
        try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune"), file("Heat"), file("Arrival")], isComplete: true)
        let arrival = try movie(f, path: "Films/Arrival.mkv")
        let heat = try movie(f, path: "Films/Heat.mkv")
        try f.store.setState(id: arrival.id, .onDevice)
        try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune")], isComplete: true, at: Date(timeIntervalSince1970: 1_000))

        #expect(try f.store.purgeRemoved(now: Date(timeIntervalSince1970: 1_000 + 29 * 86_400)).isEmpty)
        #expect(try f.store.purgeRemoved(now: Date(timeIntervalSince1970: 1_000 + 31 * 86_400)) == [heat.id])
        #expect(try f.store.movie(id: arrival.id) != nil)
    }

    /// A failing Plex URL in a download error never stores the token.
    @Test func downloadErrorHidesTokens() throws {
        let f = try makeFixture()
        try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune")], isComplete: true)
        let dune = try movie(f, path: "Films/Dune.mkv")
        try f.store.setState(
            id: dune.id, .stream,
            error: "Could not connect: https://192-168-1-2.x.plex.direct:32400/library/parts/1/file.mkv?download=1&X-Plex-Token=AbC123xyz"
        )
        let error = try #require(try f.store.movie(id: dune.id)?.downloadError)
        #expect(!error.contains("AbC123xyz"))
        #expect(error.contains("X-Plex-Token=•••"))
        #expect(error.contains("download=1"))
    }

    /// FS-23.07 §4: a Plex movie owes the server its position until it is
    /// sent; one recorded while the send was in flight still owes.
    @Test func plexPositionWaitsForSync() throws {
        let f = try makeFixture()
        let plex = MovieSource(kind: .plex, name: "Mac Studio")
        try f.store.saveSource(plex)
        try f.store.mergeScan(sourceId: plex.id, found: [ScannedMovie(plexRatingKey: "13", title: "Dune", originalFileName: "Dune.mkv", byteCount: 9)], isComplete: true)
        let dune = try #require(try f.store.movies().first)

        try f.store.recordPosition(id: dune.id, positionMs: 3_130_000, at: Date(timeIntervalSince1970: 100))
        let snapshot = try f.store.pendingPlexSync(sourceId: plex.id)
        #expect(snapshot.map(\.positionMs) == [3_130_000])

        try f.store.recordPosition(id: dune.id, positionMs: 3_140_000, at: Date(timeIntervalSince1970: 110))
        try f.store.markPlexSynced(snapshot)
        #expect(try f.store.pendingPlexSync(sourceId: plex.id).map(\.positionMs) == [3_140_000])

        try f.store.markPlexSynced(try f.store.pendingPlexSync(sourceId: plex.id))
        #expect(try f.store.pendingPlexSync(sourceId: plex.id).isEmpty)

        // A folder movie never owes Plex anything.
        try f.store.mergeScan(sourceId: f.folder.id, found: [file("Heat")], isComplete: true)
        let heat = try movie(f, path: "Films/Heat.mkv")
        try f.store.setWatched(true, ids: [heat.id])
        #expect(try f.store.movie(id: heat.id)?.plexSyncPending == false)
        #expect(try f.store.movie(id: heat.id)?.isWatched == true)
    }

    /// Deleting a subtitle clears the choice that pointed at it and drops
    /// the unfinished translation made from it; deleting the movie takes
    /// everything.
    @Test func subtitleLinksFollowTheirRows() throws {
        let f = try makeFixture()
        try f.store.mergeScan(sourceId: f.folder.id, found: [file("Dune")], isComplete: true)
        let dune = try movie(f, path: "Films/Dune.mkv")
        let en = MovieSubtitle(movieId: dune.id, language: "en", origin: .inFile, inFileTrack: 4, format: .srt, fileName: "en.srt")
        let vi = MovieSubtitle(movieId: dune.id, language: "vi", origin: .sidecar, format: .srt, fileName: "vi.srt")
        try f.store.saveSubtitle(en)
        try f.store.saveSubtitle(vi)
        try f.store.saveSubtitleChoice(MovieSubtitleChoice(movieId: dune.id, primaryId: en.id, secondaryId: vi.id))
        try f.store.saveTranslationJob(MovieTranslationJob(
            movieId: dune.id, fromSubtitleId: en.id, toLanguage: "ja", providerId: "p", cuesDone: 400, cueCount: 1_200, partialFileName: "ja.part.srt"
        ))

        try f.store.removeSubtitle(id: en.id)

        let choice = try #require(try f.store.subtitleChoice(movieId: dune.id))
        #expect(choice.primaryId == nil)
        #expect(choice.secondaryId == vi.id)
        #expect(try f.store.translationJobs(movieId: dune.id).isEmpty)

        try f.store.delete(id: dune.id)
        #expect(try f.store.subtitles(movieId: dune.id).isEmpty)
        #expect(try f.store.subtitleChoice(movieId: dune.id) == nil)
    }

    /// The library is user data outside `photo_metadata`: clearing the
    /// photo index leaves every row.
    @Test func survivesIndexClear() throws {
        let f = try makeFixture()
        try f.store.mergeScan(sourceId: f.folder.id, found: (0..<50).map { file("M\($0)") }, isComplete: true)
        try MetadataStore(database: f.database).deleteAll()
        #expect(try f.store.movies().count == 50)
        #expect(try f.store.sources().count == 1)
    }

    /// Copied-in files have no source and never clash on the unique keys.
    @Test func copiedFilesHaveNoSource() throws {
        let f = try makeFixture()
        try f.store.add(Movie(sourceId: nil, title: "Home Video", originalFileName: "a.mp4", byteCount: 5, state: .onDevice))
        try f.store.add(Movie(sourceId: nil, title: "Home Video", originalFileName: "a.mp4", byteCount: 5, state: .onDevice))
        #expect(try f.store.movies().count == 2)
    }
}
