import Foundation

/// What a subtitle's file name says (FS-23.03 §5): its format, its language
/// (`Dune.vi.srt`, `Dune.English.srt`), and which movie it belongs to.
enum SubtitleFileName {
    static let formats: [String: SubtitleParser.Format] = ["srt": .srt, "ass": .ass, "ssa": .ass, "vtt": .vtt]

    static func format(_ name: String) -> SubtitleParser.Format? {
        formats[(name as NSString).pathExtension.lowercased()]
    }

    static func isSubtitle(_ name: String) -> Bool { format(name) != nil }

    static func isZip(_ name: String) -> Bool { (name as NSString).pathExtension.lowercased() == "zip" }

    /// The last dotted or underscored tag that names a language.
    static func language(_ name: String) -> String? {
        let stem = ((name as NSString).lastPathComponent as NSString).deletingPathExtension
        let tags = stem.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == " " || $0 == "-" }).map(String.init).dropFirst()
        return tags.reversed().lazy.compactMap { MovieLanguage.code($0) }.first
    }

    /// The movie the file is named after, if one is: same title, and the
    /// same year or episode when the file names one.
    static func matchingMovie(_ name: String, in movies: [Movie]) -> Movie? {
        // `Dune.Part.Two.2024.vi.forced.srt` → `Dune.Part.Two.2024`.
        var parts = ((name as NSString).lastPathComponent as NSString).deletingPathExtension.components(separatedBy: ".")
        while parts.count > 1, let last = parts.last?.lowercased(),
              MovieLanguage.code(last) != nil || ["forced", "sdh", "cc", "hi", "full", "default"].contains(last) {
            parts.removeLast()
        }
        let parsed = MovieFileName.parse(parts.joined(separator: ".") + ".mkv")
        let wanted = key(parsed.title)
        guard !wanted.isEmpty else { return nil }
        let candidates = movies.filter { key($0.title) == wanted || key($0.displayTitle) == wanted }
        return candidates.first { movie in
            (parsed.year == nil || movie.year == parsed.year)
                && (parsed.season == nil || movie.season == parsed.season)
                && (parsed.episode == nil || movie.episode == parsed.episode)
        }
    }

    private static func key(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }
}
