import Foundation

/// One photo from a RAW and its rendered twin (FS-19.01 §3, FS-17.01 §2b):
/// a RAW and a JPEG/JPG/HEIC/HEIF (Canon writes HEIF as `.HIF`, FS-20 AC-6)
/// with the same base name, case-insensitive,
/// in the same folder, are one photo whose original is the RAW. Anything
/// else in the group — two RAWs, two JPEGs — stays a photo of its own.
///
/// A Live Photo copied out of Photos (FS-19.07 §2): one still and one movie
/// with the same base name in one folder, and no RAW, are one photo whose
/// original is the still and whose companion is the movie. This pairing
/// does not follow the RAW + JPEG switch — `IMG_1.HEIC` and `IMG_1.MOV`
/// are one picture in every app that wrote them.
enum PairingRule {
    static let renderedTwinExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "hif"]

    static func isMovie(_ name: String) -> Bool {
        FolderEnumeration.isMovie(URL(fileURLWithPath: name))
    }

    static func isRaw(_ name: String) -> Bool {
        FileTypeBadge.text(forExtension: (name as NSString).pathExtension) == "RAW"
    }

    /// A JPEG or HEIC that is not paired with the RAW beside it keeps its own
    /// sidecar, `DSC0001.JPG.xmp`: `DSC0001.xmp` is the RAW's (FS-19.01 §3).
    /// `siblings` are the other file names in its folder.
    static func usesFullNameSidecar(_ name: String, siblings: some Sequence<String>) -> Bool {
        guard renderedTwinExtensions.contains((name as NSString).pathExtension.lowercased()) else { return false }
        let base = (name as NSString).deletingPathExtension.lowercased()
        return siblings.contains { isRaw($0) && ($0 as NSString).deletingPathExtension.lowercased() == base }
    }

    struct Unit<File: Equatable>: Equatable {
        /// The original: the RAW of a pair, else the only file.
        let primary: File
        /// The rendered twin of a pair.
        let companion: File?
    }

    /// `name` reads a file's last path component; `folder` its folder (only
    /// files in one folder pair). Order follows the input.
    static func units<File: Equatable>(
        _ files: [File], pairs: Bool, livePhotos: Bool = true, name: (File) -> String, folder: (File) -> String = { _ in "" }
    ) -> [Unit<File>] {
        guard pairs || livePhotos else { return files.map { Unit(primary: $0, companion: nil) } }
        var groups: [String: [File]] = [:]
        var order: [String] = []
        for file in files {
            let key = folder(file).lowercased() + "/" + (name(file) as NSString).deletingPathExtension.lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(file)
        }
        var out: [Unit<File>] = []
        for key in order {
            let group = groups[key] ?? []
            let raws = group.filter { isRaw(name($0)) }
            let twins = group.filter { renderedTwinExtensions.contains((name($0) as NSString).pathExtension.lowercased()) }
            let movies = group.filter { isMovie(name($0)) }
            if pairs, raws.count == 1, twins.count == 1 {
                out.append(Unit(primary: raws[0], companion: twins[0]))
                out += group.filter { $0 != raws[0] && $0 != twins[0] }.map { Unit(primary: $0, companion: nil) }
            } else if livePhotos, raws.isEmpty, twins.count == 1, movies.count == 1 {
                out.append(Unit(primary: twins[0], companion: movies[0]))
                out += group.filter { $0 != twins[0] && $0 != movies[0] }.map { Unit(primary: $0, companion: nil) }
            } else {
                out += group.map { Unit(primary: $0, companion: nil) }
            }
        }
        return out
    }
}
