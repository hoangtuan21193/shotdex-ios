import Foundation

/// One photo or video in one of the folders being compared (FS-19.08 §5).
struct CommonPhotosFile: Hashable, Sendable {
    /// Which of the chosen folders, by position.
    let folder: Int
    /// Relative to that folder, `/`-separated.
    let relativePath: String
    let size: Int64
    /// Server write time: never compared, only used to reuse a SHA-256
    /// already taken.
    let modified: Date?

    var name: String { (relativePath as NSString).lastPathComponent }
    /// The folder the file sits in, relative to the chosen folder; empty at
    /// the top.
    var subfolder: String { (relativePath as NSString).deletingLastPathComponent }

    /// Name and subfolder as compared: any case, and one Unicode form — a
    /// name written on a Mac (decomposed) and on Windows (composed) is one
    /// name, and SMB shares ignore case.
    var comparableName: String { name.precomposedStringWithCanonicalMapping.lowercased() }
    var comparableSubfolder: String { subfolder.precomposedStringWithCanonicalMapping.lowercased() }
}

/// Steps 2 and 3 of the scan (FS-19.08 §5), in memory, before a byte of
/// any photo is hashed: which files can be the same photo at all, and which
/// of those look like it already.
enum CommonPhotosMatcher {
    /// The files of one size, from every folder — the only files that can
    /// hold the same bytes.
    struct SizeGroup: Equatable, Sendable {
        let size: Int64
        /// One list per folder, in folder order, none of them empty.
        let files: [[CommonPhotosFile]]
    }

    /// The sizes present in every folder, largest first. A file whose size
    /// one folder lacks is dropped here, unread; so is an empty file, which
    /// every other empty file would "match".
    static func sizeGroups(_ folders: [[CommonPhotosFile]]) -> [SizeGroup] {
        guard folders.count >= 2 else { return [] }
        let bySize = folders.map { Dictionary(grouping: $0.filter { $0.size > 0 }, by: \.size) }
        guard let fewest = bySize.min(by: { $0.count < $1.count }) else { return [] }
        var groups: [SizeGroup] = []
        for size in fewest.keys {
            let perFolder = bySize.map { $0[size] ?? [] }
            guard perFolder.allSatisfy({ !$0.isEmpty }) else { continue }
            groups.append(SizeGroup(size: size, files: perFolder))
        }
        return groups.sorted { $0.size > $1.size }
    }

    /// The files of a group that look like one photo in every folder —
    /// Likely the same: besides the size, the same name (any case), the same
    /// subfolder below the chosen folder, or the same capture time
    /// (`captureKeys`, from `CommonPhotosCaptureKey`). Two files at the top of
    /// their folders do not share a subfolder; that would make every pair of
    /// equal sizes there look alike. The sign may differ from one folder to
    /// the next — a hint, not a proof; only the SHA-256 makes it Same.
    static func likely(_ group: SizeGroup, captureKeys: [CommonPhotosFile: String] = [:]) -> Set<CommonPhotosFile> {
        struct Marks {
            var names: Set<String> = []
            var subfolders: Set<String> = []
            var keys: Set<String> = []
        }
        let marks = group.files.map { files in
            files.reduce(into: Marks()) { marks, file in
                marks.names.insert(file.comparableName)
                if !file.subfolder.isEmpty { marks.subfolders.insert(file.comparableSubfolder) }
                if let key = captureKeys[file] { marks.keys.insert(key) }
            }
        }
        var out = Set<CommonPhotosFile>()
        for (index, files) in group.files.enumerated() {
            for file in files {
                let name = file.comparableName
                let subfolder = file.comparableSubfolder
                let key = captureKeys[file]
                let inEvery = marks.indices.allSatisfy { other in
                    other == index
                        || marks[other].names.contains(name)
                        || (!subfolder.isEmpty && marks[other].subfolders.contains(subfolder))
                        || (key.map { marks[other].keys.contains($0) } ?? false)
                }
                if inEvery { out.insert(file) }
            }
        }
        return out
    }

    /// What the sheet shows before any hashing: candidates counted in the
    /// first folder, since a common photo is in every folder once at least.
    struct Preview: Equatable, Sendable {
        var groups: [SizeGroup]
        var likely: Set<CommonPhotosFile>
        /// First-folder files that can still be common.
        var candidateCount: Int
        var candidateBytes: Int64
        /// First-folder files among them that look like the same photo.
        var likelyCount: Int
    }

    static func preview(_ folders: [[CommonPhotosFile]], captureKeys: [CommonPhotosFile: String] = [:]) -> Preview {
        let groups = sizeGroups(folders)
        var likelySet = Set<CommonPhotosFile>()
        for group in groups { likelySet.formUnion(likely(group, captureKeys: captureKeys)) }
        let first = groups.flatMap { $0.files[0] }
        return Preview(groups: groups, likely: likelySet,
                       candidateCount: first.count,
                       candidateBytes: first.reduce(0) { $0 + $1.size },
                       likelyCount: first.filter { likelySet.contains($0) }.count)
    }

    /// Of one size group, the files whose key (a sample fingerprint or a
    /// SHA-256) turns up in every folder, by key. A file with no key is
    /// dropped; a key one folder lacks drops every file holding it.
    static func shared(_ files: [[CommonPhotosFile]], keys: [CommonPhotosFile: String]) -> [String: [[CommonPhotosFile]]] {
        let byKey = files.map { folderFiles in
            Dictionary(grouping: folderFiles.filter { keys[$0] != nil }) { keys[$0]! }
        }
        guard let fewest = byKey.min(by: { $0.count < $1.count }) else { return [:] }
        var out: [String: [[CommonPhotosFile]]] = [:]
        for key in fewest.keys {
            let perFolder = byKey.map { $0[key] ?? [] }
            if perFolder.allSatisfy({ !$0.isEmpty }) { out[key] = perFolder }
        }
        return out
    }
}

/// A photo every chosen folder holds, byte for byte (FS-19.08 §5 step 4):
/// Same. Only these are copied or moved.
struct CommonPhoto: Equatable, Sendable {
    let sha256: String
    let size: Int64
    /// One list per folder, in folder order — a folder may hold the photo
    /// more than once.
    let files: [[CommonPhotosFile]]
}
