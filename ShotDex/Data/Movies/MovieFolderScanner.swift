import Foundation

/// Lists a folder source (FS-23.01 §2): every movie file in the folder and
/// its subfolders, by name and size only — no file is opened (AC-43). The
/// subtitles and the poster image beside each movie come from the same
/// listings.
enum MovieFolderScanner {
    struct Result: Sendable {
        var movies: [ScannedMovie]
        /// Every folder answered. A folder that failed leaves this false so
        /// the merge removes nothing it could not see.
        var isComplete: Bool
        /// The top folder answered at all — false means the source is out
        /// of reach (FS-23.01 §3: its posters dim).
        var reachedRoot: Bool
    }

    static let subtitleExtensions: [String: MovieSubtitle.Format] = ["srt": .srt, "ass": .ass, "ssa": .ass, "vtt": .vtt]
    /// NAS housekeeping folders, never a library.
    static let skippedFolders: Set<String> = ["@eadir", "#recycle", "$recycle.bin", "#snapshot", ".snapshot", "lost+found", "system volume information"]
    static let maxDepth = 8

    static func scan(_ client: any RemoteFileClient, folder: String) async -> Result {
        var movies: [ScannedMovie] = []
        var isComplete = true
        var reachedRoot = false
        var queue: [(path: String, depth: Int)] = [(ServerUploadPath.normalizedFolder(folder), 0)]
        while !queue.isEmpty {
            let (path, depth) = queue.removeFirst()
            if Task.isCancelled { return Result(movies: movies, isComplete: false, reachedRoot: reachedRoot) }
            let entries: [RemoteEntry]
            do {
                entries = try await client.entries(in: path)
                if depth == 0 { reachedRoot = true }
            } catch {
                isComplete = false
                continue
            }
            let files = entries.filter { !$0.isDirectory && !$0.name.hasPrefix(".") }
            let names = files.map(\.name)
            let movieFiles = files.filter { MovieFileName.isMovie($0.name) }
            for file in movieFiles {
                movies.append(scanned(file, in: path, siblings: names, moviesInFolder: movieFiles.count))
            }
            if depth < maxDepth {
                for entry in entries where entry.isDirectory && !entry.name.hasPrefix(".")
                    && !skippedFolders.contains(entry.name.lowercased()) {
                    queue.append((ServerUploadPath.join(path, entry.name), depth + 1))
                }
            }
        }
        return Result(movies: movies, isComplete: isComplete, reachedRoot: reachedRoot)
    }

    static func scanned(_ file: RemoteEntry, in folder: String, siblings: [String], moviesInFolder: Int) -> ScannedMovie {
        let parsed = MovieFileName.parse(file.name)
        let poster = MoviePosterResolver.candidates(
            fileName: file.name, siblings: siblings, moviesInFolder: moviesInFolder, canOpenFile: false, title: parsed.title, palette: 1
        ).compactMap { candidate -> String? in
            if case .sidecar(let name) = candidate { return ServerUploadPath.join(folder, name) }
            return nil
        }.first
        return ScannedMovie(
            remotePath: ServerUploadPath.join(folder, file.name),
            title: parsed.title, year: parsed.year, season: parsed.season, episode: parsed.episode,
            originalFileName: file.name, byteCount: file.size,
            posterPath: poster,
            subtitles: subtitles(for: file.name, in: folder, siblings: siblings)
        )
    }

    /// `Dune.srt`, `Dune.en.srt`, `Dune.English.forced.srt` beside `Dune.mkv`.
    static func subtitles(for movie: String, in folder: String, siblings: [String]) -> [ScannedSubtitle] {
        let base = (movie as NSString).deletingPathExtension.lowercased()
        return siblings.compactMap { name in
            let ext = (name as NSString).pathExtension.lowercased()
            guard let format = subtitleExtensions[ext] else { return nil }
            let stem = (name as NSString).deletingPathExtension
            let lowered = stem.lowercased()
            guard lowered == base || lowered.hasPrefix(base + ".") || lowered.hasPrefix(base + "_") else { return nil }
            let tags = stem.dropFirst(base.count).split(whereSeparator: { $0 == "." || $0 == "_" }).map(String.init)
            let language = tags.lazy.compactMap { MovieLanguage.code($0) }.first
            return ScannedSubtitle(remotePath: ServerUploadPath.join(folder, name), language: language, format: format)
        }
        .sorted { $0.remotePath < $1.remotePath }
    }
}
