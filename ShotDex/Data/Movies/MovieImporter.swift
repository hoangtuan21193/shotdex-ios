import Foundation

/// Add Movie Files…, the Share sheet and AirDrop (FS-23.01 §2, AC-6): the
/// files are **copied** into `Movies/<id>/` — the original stays where it
/// was — and count as downloaded. Subtitle files picked or shared with a
/// movie of the same name come along. A movie already here (same movie
/// hash, FS-23.05 §3) is not copied twice.
struct MovieImporter: Sendable {
    let store: MovieStore
    let files: MovieFileStore

    struct Result: Equatable, Sendable {
        /// New or already-present movies, in the order given.
        var movieIds: [String] = []
        var skippedDuplicates = 0
        /// Files that are neither a movie nor a subtitle beside one.
        var ignored: [String] = []
    }

    func importFiles(_ urls: [URL], at date: Date = Date()) throws -> Result {
        var result = Result()
        try files.prepare()
        let names = urls.map(\.lastPathComponent)
        let movies = urls.filter { MovieFileName.isMovie($0.lastPathComponent) }
        let existing = try store.movies()
        var claimed = Set<String>()
        for url in movies {
            try Self.accessing(url) {
                let hash = try MovieHash.compute(fileAt: url)
                if let already = existing.first(where: { $0.fileHash == hash && $0.isOnDevice }) {
                    result.movieIds.append(already.id)
                    result.skippedDuplicates += 1
                    return
                }
                let parsed = MovieFileName.parse(url.lastPathComponent)
                let size = Int64((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
                var movie = Movie(
                    sourceId: nil, title: parsed.title, year: parsed.year, season: parsed.season, episode: parsed.episode,
                    originalFileName: url.lastPathComponent, byteCount: size, fileHash: hash,
                    state: .onDevice, downloadedBytes: size, addedAt: Int(date.timeIntervalSince1970)
                )
                let folder = files.directory(for: movie.id)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = MovieFileStore.safeName(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: folder.appending(path: name))
                movie.localFileName = name
                try store.add(movie)
                result.movieIds.append(movie.id)

                for subtitle in MovieFolderScanner.subtitles(for: url.lastPathComponent, in: "", siblings: names) {
                    guard let source = urls.first(where: { $0.lastPathComponent == subtitle.remotePath }) else { continue }
                    claimed.insert(source.lastPathComponent)
                    try Self.accessing(source) {
                        let row = MovieSubtitle(movieId: movie.id, language: subtitle.language, origin: .sidecar, format: subtitle.format, fileName: "")
                        let data = try Data(contentsOf: source)
                        var saved = row
                        saved.fileName = try files.write(data, named: "\(row.id).\(row.format.rawValue)", for: movie.id)
                        try store.saveSubtitle(saved)
                    }
                }
            }
        }
        result.ignored = names.filter { !MovieFileName.isMovie($0) && !claimed.contains($0) }
        return result
    }

    /// A file from Files or another app: readable only inside its security
    /// scope.
    private static func accessing(_ url: URL, _ body: () throws -> Void) throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        try body()
    }
}
