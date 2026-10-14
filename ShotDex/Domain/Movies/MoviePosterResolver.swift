import Foundation

/// Where a movie's poster comes from, best first (FS-23.01 §4, AC-43).
enum MoviePosterSource: Equatable, Sendable {
    /// Plex's poster (`thumb`), fetched resized.
    case plex(thumb: String)
    /// An image next to the movie on the source, by file name.
    case sidecar(String)
    /// Cover art inside an MP4/M4V/MOV — read from the header, which a scan
    /// may do.
    case embeddedMP4
    /// Cover art inside an MKV — an attachment that can sit anywhere in the
    /// file, so only once the movie is here or has been opened.
    case embeddedMKV
    /// A frame at 10 % of the running time, likewise.
    case frame
    /// The fallback that is always there: title and year on a color picked
    /// from the title.
    case titleTile(colorIndex: Int)
}

enum MoviePosterResolver {
    static let imageExtensions = ["jpg", "jpeg", "png"]

    /// - Parameters:
    ///   - fileName: the movie's file name.
    ///   - siblings: every file name in the movie's folder, as the scan
    ///     listed it (no extra request).
    ///   - moviesInFolder: how many movies that folder holds — a
    ///     `poster.jpg` speaks for a folder of one, not for a shelf.
    ///   - canOpenFile: on the device, or opened in the player before:
    ///     reading the whole file for art costs nothing extra.
    static func candidates(
        plexThumb: String? = nil,
        fileName: String,
        siblings: [String] = [],
        moviesInFolder: Int = 1,
        canOpenFile: Bool,
        title: String,
        palette: Int
    ) -> [MoviePosterSource] {
        var out: [MoviePosterSource] = []
        if let plexThumb, !plexThumb.isEmpty { out.append(.plex(thumb: plexThumb)) }

        let byLowercase = Dictionary(siblings.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let base = (fileName as NSString).deletingPathExtension.lowercased()
        var names = imageExtensions.map { "\(base)-poster.\($0)" }
        if moviesInFolder == 1 {
            names += imageExtensions.map { "poster.\($0)" } + imageExtensions.map { "folder.\($0)" }
        }
        for name in names {
            if let found = byLowercase[name] { out.append(.sidecar(found)) }
        }

        switch (fileName as NSString).pathExtension.lowercased() {
        case "mp4", "m4v", "mov": out.append(.embeddedMP4)
        case "mkv", "webm": if canOpenFile { out.append(.embeddedMKV) }
        default: break
        }
        if canOpenFile { out.append(.frame) }
        out.append(.titleTile(colorIndex: colorIndex(for: title, palette: palette)))
        return out
    }

    /// Stable across launches (unlike `hashValue`), so a tile keeps its
    /// color: FNV-1a over the folded title, high bits — FNV's low bits barely
    /// move between titles that differ only early on.
    static func colorIndex(for title: String, palette: Int) -> Int {
        guard palette > 0 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01b3
        }
        return Int((hash >> 40) % UInt64(palette))
    }
}
