import Foundation

/// One photo from a RAW and its rendered twin (FS-19.01 §3, FS-17.01 §2b):
/// a RAW and a JPEG/JPG/HEIC/HEIF with the same base name, case-insensitive,
/// in the same folder, are one photo whose original is the RAW. Anything
/// else in the group — two RAWs, two JPEGs — stays a photo of its own.
enum PairingRule {
    static let renderedTwinExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif"]

    struct Unit<File: Equatable>: Equatable {
        /// The original: the RAW of a pair, else the only file.
        let primary: File
        /// The rendered twin of a pair.
        let companion: File?
    }

    /// `name` reads a file's last path component; `folder` its folder (only
    /// files in one folder pair). Order follows the input.
    static func units<File: Equatable>(
        _ files: [File], pairs: Bool, name: (File) -> String, folder: (File) -> String = { _ in "" }
    ) -> [Unit<File>] {
        guard pairs else { return files.map { Unit(primary: $0, companion: nil) } }
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
            let raws = group.filter { FileTypeBadge.text(forExtension: (name($0) as NSString).pathExtension) == "RAW" }
            let twins = group.filter { renderedTwinExtensions.contains((name($0) as NSString).pathExtension.lowercased()) }
            if raws.count == 1, twins.count == 1 {
                out.append(Unit(primary: raws[0], companion: twins[0]))
                out += group.filter { $0 != raws[0] && $0 != twins[0] }.map { Unit(primary: $0, companion: nil) }
            } else {
                out += group.map { Unit(primary: $0, companion: nil) }
            }
        }
        return out
    }
}
