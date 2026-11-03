import Foundation

/// "Only new photos" (FS-19.08 §6c): a set — connection, source folders in
/// any order, destination — that already gathered checks only photos with
/// at least one copy new or changed since: a path, size and write time no
/// finished run of the set has seen. A photo only one folder has is not
/// common yet and waits, as any scan does.
enum CommonPhotosIncremental {
    /// One file as a run saw it.
    struct Stamp: Hashable, Sendable {
        var path: String
        var size: Int64
        /// Nil on a server that gives none: then path and size alone say
        /// "the same file".
        var modifiedAt: Int?
    }

    /// The set two runs share when they gather the same folders to the same
    /// place; Copy or Move does not matter.
    static func setKey(connectionId: String, folders: [String], destination: String) -> String {
        let sources = folders.map(ServerUploadPath.normalizedFolder).sorted()
        return ([connectionId] + sources + ["→", ServerUploadPath.normalizedFolder(destination)]).joined(separator: "\u{1F}")
    }

    static func stamp(_ file: CommonPhotosFile, folders: [String]) -> Stamp {
        Stamp(path: ServerUploadPath.join(folders[file.folder], file.relativePath), size: file.size,
              modifiedAt: file.modified.map { Int($0.timeIntervalSince1970) })
    }

    /// Whether a run of the set saw this very file.
    static func wasSeen(_ file: CommonPhotosFile, folders: [String], seen: Set<Stamp>) -> Bool {
        seen.contains(stamp(file, folders: folders))
    }

    /// The listing cut to the sizes that hold a file no run has seen: a size
    /// whose every file was seen can only make photos already gathered, so
    /// none of it is read — Copy or Move.
    static func listing(_ files: [[CommonPhotosFile]], folders: [String], seen: Set<Stamp>) -> [[CommonPhotosFile]] {
        guard !seen.isEmpty else { return files }
        let fresh = Set(files.joined().filter { !wasSeen($0, folders: folders, seen: seen) }.map(\.size))
        return files.map { $0.filter { fresh.contains($0.size) } }
    }

    /// The photos with at least one copy no run has seen.
    static func newPhotos(_ photos: [CommonPhoto], folders: [String], seen: Set<Stamp>) -> [CommonPhoto] {
        guard !seen.isEmpty else { return photos }
        return photos.filter { photo in photo.files.joined().contains { !wasSeen($0, folders: folders, seen: seen) } }
    }
}
