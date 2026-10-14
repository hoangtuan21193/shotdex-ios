import Foundation
import Testing
@testable import ShotDex

/// FS-23.01 §4, AC-43: where a poster comes from, best first.
@Suite struct MoviePosterResolverTests {
    /// AC-43's folder: A has poster.jpg, B.mp4 has cover art, C.mkv nothing.
    @Test func order() {
        let a = MoviePosterResolver.candidates(fileName: "A.mkv", siblings: ["A.mkv", "Poster.JPG", "A.en.srt"], canOpenFile: false, title: "A", palette: 8)
        #expect(a.first == .sidecar("Poster.JPG"))

        let b = MoviePosterResolver.candidates(fileName: "B.mp4", siblings: ["B.mp4"], canOpenFile: false, title: "B", palette: 8)
        #expect(b.first == .embeddedMP4)

        // Streamed MKV: a scan never opens it — straight to the title tile.
        let c = MoviePosterResolver.candidates(fileName: "C.mkv", siblings: ["C.mkv"], canOpenFile: false, title: "C", palette: 8)
        #expect(c.count == 1)
        guard case .titleTile = c.first else { Issue.record("expected the title tile"); return }

        // Downloaded C: its own art, then a frame, then the tile.
        let downloaded = MoviePosterResolver.candidates(fileName: "C.mkv", canOpenFile: true, title: "C", palette: 8)
        #expect(Array(downloaded.prefix(2)) == [.embeddedMKV, .frame])
    }

    @Test func plexFirstThenNamedSidecarThenFolderImages() {
        let found = MoviePosterResolver.candidates(
            plexThumb: "/library/metadata/13/thumb/1", fileName: "Dune.mkv",
            siblings: ["Dune.mkv", "folder.jpg", "dune-poster.png", "poster.jpg"],
            canOpenFile: false, title: "Dune", palette: 8
        )
        #expect(Array(found.prefix(4)) == [
            .plex(thumb: "/library/metadata/13/thumb/1"), .sidecar("dune-poster.png"), .sidecar("poster.jpg"), .sidecar("folder.jpg"),
        ])
    }

    /// A shelf folder's poster.jpg is not every movie's poster.
    @Test func sharedFolderPosterIgnored() {
        let found = MoviePosterResolver.candidates(fileName: "Heat.mkv", siblings: ["Heat.mkv", "Dune.mkv", "poster.jpg"], moviesInFolder: 2, canOpenFile: false, title: "Heat", palette: 8)
        #expect(!found.contains(.sidecar("poster.jpg")))
    }

    @Test func tileColorIsStable() {
        let first = MoviePosterResolver.colorIndex(for: "Perfect Days", palette: 8)
        #expect(first == MoviePosterResolver.colorIndex(for: "perfect days", palette: 8))
        #expect((0..<8).contains(first))
        #expect(MoviePosterResolver.colorIndex(for: "Perfect Days", palette: 8) == first)
        let spread = Set(["Dune", "Heat", "Arrival", "Past Lives", "Perfect Days", "Alien", "Up", "Her"].map { MoviePosterResolver.colorIndex(for: $0, palette: 8) })
        #expect(spread.count >= 4)
    }
}
