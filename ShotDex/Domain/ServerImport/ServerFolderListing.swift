import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One item a server folder listing returns.
struct RemoteEntry: Hashable, Sendable {
    let name: String
    let isDirectory: Bool
    let size: Int64
    /// Last write time, when the server reports one.
    let modified: Date?
}

/// One photo on the server as the grid shows it (FS-17.01 §2): a single
/// image file, or a RAW with its JPEG/HEIC twin folded into one tile.
struct ServerPhoto: Identifiable, Hashable, Sendable {
    /// The files in download order: the rendered twin first, then the RAW —
    /// the order PhotoKit takes them as `.photo` and `.alternatePhoto`.
    let files: [RemoteEntry]

    /// The name of the first file: unique within a folder.
    var id: String { files[0].name }

    /// The file thumbnails and dates come from: the rendered twin when there
    /// is one — smaller, and every reader handles it.
    var primary: RemoteEntry { files[0] }

    var raw: RemoteEntry? { files.first { ServerFolderListing.isRAW($0.name) } }

    var isPair: Bool { files.count == 2 }

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    /// `RAW+JPG`, `RAW+HEIC`, or the single file's badge (`FileTypeBadge`).
    var badge: String {
        let primaryBadge = FileTypeBadge.text(forExtension: (primary.name as NSString).pathExtension) ?? "PHOTO"
        return isPair ? "RAW+\(primaryBadge)" : primaryBadge
    }

    /// Newest write time of the files, for Date Modified.
    var modified: Date? { files.compactMap(\.modified).max() }
}

/// What a folder shows: subfolders, photos, and the files that are not
/// photos.
struct ServerFolderContents: Equatable, Sendable {
    var folders: [String]
    var photos: [ServerPhoto]
    /// Files that are neither images nor dot files (videos, sidecars,
    /// documents): hidden unless Show All Files is on (FS-17.01 §2c), in
    /// Finder order.
    var others: [RemoteEntry] = []
    /// Folder write times, for the List view's second line.
    var folderModified: [String: Date] = [:]

    /// The "M other files hidden" line.
    var hiddenFileCount: Int { others.count }

    static let empty = ServerFolderContents(folders: [], photos: [])
}

/// Turns a raw listing into what the browser shows (FS-17.01 §2): images
/// only, RAW + JPEG/HEIC pairs folded, dot files ignored.
enum ServerFolderListing {
    /// Every extension ImageIO can read that is an image — from the system,
    /// so a format iOS learns to read later shows up with no change here.
    static let imageExtensions: Set<String> = {
        let identifiers = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
        var extensions = Set<String>()
        for identifier in identifiers {
            guard let type = UTType(identifier), type.conforms(to: .image) else { continue }
            for ext in type.tags[.filenameExtension] ?? [] {
                extensions.insert(ext.lowercased())
            }
        }
        return extensions
    }()

    /// Extensions a RAW pairs with.
    static let renderedTwinExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif"]

    static func isRAW(_ name: String) -> Bool {
        FileTypeBadge.text(forExtension: (name as NSString).pathExtension) == "RAW"
    }

    static func isImage(_ name: String, extensions: Set<String> = imageExtensions) -> Bool {
        extensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func contents(of entries: [RemoteEntry], imageExtensions: Set<String> = imageExtensions) -> ServerFolderContents {
        var folders: [String] = []
        var images: [RemoteEntry] = []
        var others: [RemoteEntry] = []
        var folderModified: [String: Date] = [:]
        for entry in entries where !entry.name.hasPrefix(".") && entry.name != "." && entry.name != ".." {
            if entry.isDirectory {
                folders.append(entry.name)
                folderModified[entry.name] = entry.modified
            } else if isImage(entry.name, extensions: imageExtensions) {
                images.append(entry)
            } else {
                others.append(entry)
            }
        }

        let groups = Dictionary(grouping: images) { ($0.name as NSString).deletingPathExtension.lowercased() }
        var photos: [ServerPhoto] = []
        for (_, group) in groups {
            let raws = group.filter { isRAW($0.name) }
            let twins = group.filter { renderedTwinExtensions.contains(($0.name as NSString).pathExtension.lowercased()) }
            if raws.count == 1, twins.count == 1 {
                photos.append(ServerPhoto(files: [twins[0], raws[0]]))
                photos += group.filter { $0 != raws[0] && $0 != twins[0] }.map { ServerPhoto(files: [$0]) }
            } else {
                photos += group.map { ServerPhoto(files: [$0]) }
            }
        }

        return ServerFolderContents(
            folders: RemoteFolderListing.visible(folders),
            photos: photos.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending },
            others: others.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            folderModified: folderModified
        )
    }
}
