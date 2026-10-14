import Foundation

/// Title, year and episode read from a release-style file name when the
/// source has nothing better (FS-23.01 §4):
/// `Dune.Part.Two.2024.2160p.x265.mkv` → `Dune Part Two` · 2024,
/// `Severance.S02E04.Woe's.Hollow.1080p.mkv` → `Severance` · S2 E4.
struct MovieFileName: Equatable, Sendable {
    var title: String
    var year: Int?
    var season: Int?
    var episode: Int?

    init(title: String, year: Int? = nil, season: Int? = nil, episode: Int? = nil) {
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
    }

    /// File extensions Movies takes (FS-23.01 §2).
    static let movieExtensions: Set<String> = ["mp4", "m4v", "mov", "mkv", "webm", "flv", "avi", "wmv", "ts", "m2ts"]

    static func isMovie(_ fileName: String) -> Bool {
        movieExtensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    /// Words that start the technical tail of a release name: nothing from
    /// the first of these on is part of the title.
    private static let tags: Set<String> = [
        "2160p", "1080p", "1080i", "720p", "576p", "480p", "4k", "uhd", "hd", "fhd", "sd",
        "bluray", "blu-ray", "bdrip", "brrip", "bdremux", "remux", "web", "web-dl", "webdl", "webrip", "hdtv", "dvdrip",
        "dvd", "hdrip", "hdcam", "cam", "ts", "proper", "repack", "extended", "unrated", "remastered", "imax",
        "x264", "x265", "h264", "h265", "h.264", "h.265", "hevc", "avc", "av1", "xvid", "divx", "vp9",
        "hdr", "hdr10", "hdr10+", "dv", "dovi", "sdr", "10bit", "8bit",
        "aac", "ac3", "eac3", "dd5.1", "ddp5.1", "dts", "dts-hd", "truehd", "atmos", "flac", "mp3", "5.1", "7.1", "2.0",
        "multi", "dual", "subbed", "dubbed",
    ]

    static func parse(_ fileName: String) -> MovieFileName {
        var base = (fileName as NSString).lastPathComponent
        if movieExtensions.contains((base as NSString).pathExtension.lowercased()) {
            base = (base as NSString).deletingPathExtension
        }
        // A leading [Group] or {tag} is never the title.
        base = base.replacing(#/^\s*[\[{][^\]}]*[\]}]\s*/#, with: "")
        let spaced = base
            .replacing(#/[._]/#, with: " ")
            .replacing(#/[\[\](){}]/#, with: " ")
        let words = spaced.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        // S01E04, s1e4, 1x04
        for (index, word) in words.enumerated() {
            if let match = word.wholeMatch(of: #/(?i)s(\d{1,2})e(\d{1,3})(?:e\d{1,3})*/#) ?? word.wholeMatch(of: #/(\d{1,2})x(\d{2,3})/#),
               let season = Int(match.1), let episode = Int(match.2) {
                let title = clean(words[..<index])
                return MovieFileName(title: title.isEmpty ? base : title, season: season, episode: episode)
            }
        }

        let tagStart = words.firstIndex { tags.contains($0.lowercased()) } ?? words.count
        // The year is the last 19xx/20xx before the tags that is not the
        // whole title: `2001 A Space Odyssey 1968`, `Blade Runner 2049 2017`,
        // `1917 2019`.
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        var yearIndex: Int?
        for index in stride(from: tagStart - 1, through: 1, by: -1) {
            if let value = Int(words[index]), words[index].count == 4, (1900...currentYear + 1).contains(value) {
                yearIndex = index
                break
            }
        }
        if let yearIndex {
            return MovieFileName(title: clean(words[..<yearIndex]), year: Int(words[yearIndex]))
        }
        let title = clean(words[..<tagStart])
        return MovieFileName(title: title.isEmpty ? clean(words[...]) : title)
    }

    private static func clean(_ words: ArraySlice<String>) -> String {
        words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–"))
            .replacing(#/\s{2,}/#, with: " ")
    }
}
