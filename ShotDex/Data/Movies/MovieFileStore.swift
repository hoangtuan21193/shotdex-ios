import Foundation

/// Where Movies keeps files on the device (FS-23.05 §1): `Movies/<id>/`
/// for downloaded and copied-in movies with their subtitles and art,
/// `Movies/.incoming/` for downloads in progress. In Application Support —
/// not Documents (it must not show in Files), not Caches (the system may
/// empty Caches when the device is full, and these are the user's) — and
/// excluded from iCloud backup as a whole.
struct MovieFileStore: Sendable {
    let root: URL

    static var standard: MovieFileStore {
        MovieFileStore(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Movies", directoryHint: .isDirectory))
    }

    var incoming: URL { root.appending(path: ".incoming", directoryHint: .isDirectory) }

    func directory(for movieId: String) -> URL {
        root.appending(path: movieId, directoryHint: .isDirectory)
    }

    func partFile(for movieId: String) -> URL {
        incoming.appending(path: "\(movieId).part")
    }

    func file(for movie: Movie) -> URL? {
        movie.localFileName.map { directory(for: movie.id).appending(path: $0) }
    }

    /// Creates the folders and keeps them out of backups (AC-10).
    func prepare() throws {
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        var root = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }

    var isExcludedFromBackup: Bool {
        (try? root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
    }

    /// Bytes of a download so far.
    func partSize(for movieId: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: partFile(for: movieId).path)[.size] as? Int64) ?? 0
    }

    /// The finished part becomes `Movies/<id>/<name>`.
    func finish(_ movieId: String, as fileName: String) throws -> URL {
        let folder = directory(for: movieId)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: Self.safeName(fileName))
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partFile(for: movieId), to: target)
        return target
    }

    func write(_ data: Data, named name: String, for movieId: String) throws -> String {
        let folder = directory(for: movieId)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = Self.safeName(name)
        try data.write(to: folder.appending(path: safe), options: .atomic)
        return safe
    }

    /// Remove Download / Remove from Movies: everything of that movie here.
    func removeAll(for movieId: String) {
        try? FileManager.default.removeItem(at: directory(for: movieId))
        try? FileManager.default.removeItem(at: partFile(for: movieId))
    }

    func removePart(for movieId: String) {
        try? FileManager.default.removeItem(at: partFile(for: movieId))
    }

    /// Launch sweep (FS-23.05 §1): folders and parts no row explains go;
    /// returns rows that say "on the device" with no file there, so the
    /// caller marks them Missing — never deletes them.
    func sweep(movies: [Movie]) -> [String] {
        let known = Set(movies.map(\.id))
        let downloading = Set(movies.filter { $0.state == .downloading || $0.state == .queued }.map(\.id))
        let fm = FileManager.default
        for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent != ".incoming" && !known.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
        for url in (try? fm.contentsOfDirectory(at: incoming, includingPropertiesForKeys: nil)) ?? [] {
            let id = url.deletingPathExtension().lastPathComponent
            if !downloading.contains(id) { try? fm.removeItem(at: url) }
        }
        return movies.filter { movie in
            movie.state == .onDevice && !(file(for: movie).map { fm.fileExists(atPath: $0.path) } ?? false)
        }.map(\.id)
    }

    /// A file name from a server, safe as one path component.
    static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "movie" : cleaned
    }
}
