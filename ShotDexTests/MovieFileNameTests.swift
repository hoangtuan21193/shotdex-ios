import Foundation
import Testing
@testable import ShotDex

/// FS-23.01 §4: title and year from a release-style file name.
@Suite struct MovieFileNameTests {
    @Test(arguments: [
        // AC-2's three movies.
        ("Dune.Part.Two.2024.2160p.x265.mkv", "Dune Part Two", 2024),
        ("Perfect.Days.2023.1080p.mkv", "Perfect Days", 2023),
        ("Past.Lives.2023.mp4", "Past Lives", 2023),
        // Years inside titles.
        ("2001.A.Space.Odyssey.1968.1080p.BluRay.mkv", "2001 A Space Odyssey", 1968),
        ("Blade.Runner.2049.2017.2160p.UHD.BluRay.x265-GRP.mkv", "Blade Runner 2049", 2017),
        ("1917.2019.mkv", "1917", 2019),
        // Other spellings.
        ("The Matrix (1999).mkv", "The Matrix", 1999),
        ("[YTS] Spirited_Away_2001_720p.mp4", "Spirited Away", 2001),
        ("Amélie.2001.FRENCH.1080p.WEB-DL.DDP5.1.H.264.mkv", "Amélie", 2001),
        ("In.the.Mood.for.Love.2000.Criterion.REMUX.mkv", "In the Mood for Love", 2000),
    ] as [(String, String, Int)])
    func titleAndYear(name: String, title: String, year: Int) {
        let parsed = MovieFileName.parse(name)
        #expect(parsed == MovieFileName(title: title, year: year))
    }

    @Test func noYear() {
        #expect(MovieFileName.parse("Home.Video.1080p.mp4") == MovieFileName(title: "Home Video"))
        #expect(MovieFileName.parse("1917.mkv") == MovieFileName(title: "1917"))
        #expect(MovieFileName.parse("IMG_0042.MOV") == MovieFileName(title: "IMG 0042"))
    }

    @Test(arguments: [
        ("Severance.S02E04.Woe's.Hollow.1080p.ATVP.WEB-DL.mkv", "Severance", 2, 4),
        ("the.bear.s3e10.mkv", "the bear", 3, 10),
        ("Shogun - 1x07 - A Dagger in the Heart.mkv", "Shogun", 1, 7),
        ("Doctor.Who.2005.S01E01E02.mkv", "Doctor Who 2005", 1, 1),
    ] as [(String, String, Int, Int)])
    func episodes(name: String, title: String, season: Int, episode: Int) {
        #expect(MovieFileName.parse(name) == MovieFileName(title: title, season: season, episode: episode))
    }

    @Test func movieExtensions() {
        #expect(MovieFileName.isMovie("a.MKV"))
        #expect(MovieFileName.isMovie("clip.m2ts"))
        #expect(!MovieFileName.isMovie("a.srt"))
        #expect(!MovieFileName.isMovie("poster.jpg"))
    }
}
