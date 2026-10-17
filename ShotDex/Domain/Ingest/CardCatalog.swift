import Foundation

/// One file a memory card lists (FS-20 §5), read from its directory only —
/// no byte of the file itself.
struct CardFile: Sendable, Hashable {
    /// Relative to the card's root, `/`-separated: `DCIM/100CANON/IMG_0042.CR3`.
    let path: String
    let size: Int64
    /// The file's date on the card; the grid and the import history use it
    /// until EXIF is read (FS-20 plan K6).
    let modified: Date?

    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }
    var pathExtension: String { (name as NSString).pathExtension.lowercased() }
}

/// One tile of the Import from Card grid: a photo with every file that goes
/// with it (a RAW and its JPEG or HEIF), or a video.
struct CardItem: Sendable, Hashable, Identifiable {
    enum Kind: Sendable, Hashable { case photo, video }

    let kind: Kind
    /// The original first: the RAW of a pair, else the only file.
    let files: [CardFile]

    var primary: CardFile { files[0] }
    /// The primary file's path on the card.
    var id: String { primary.path }
    var byteCount: Int64 { files.reduce(0) { $0 + $1.size } }
    var date: Date? { primary.modified }
}

/// A card's file list as grid tiles (FS-20 §5): a RAW and its rendered twin
/// with the same name in the same folder are one tile, by the same rule as
/// a folder source (`PairingRule`); a WAV voice memo rides with the photo of
/// its name; a clip is a tile of its own. The camera's own files — `.THM`
/// thumbnails, the MISC folder, catalogs, anything hidden — are left out.
/// Oldest first.
enum CardCatalog {
    static let movieExtensions: Set<String> = ["mp4", "mov"]
    static let audioExtensions: Set<String> = ["wav"]

    static func items(_ files: [CardFile]) -> [CardItem] {
        var photos: [CardFile] = []
        var movies: [CardFile] = []
        var audio: [String: CardFile] = [:]
        for file in files where isListed(file) {
            let ext = file.pathExtension
            if movieExtensions.contains(ext) {
                movies.append(file)
            } else if audioExtensions.contains(ext) {
                audio[pairKey(file)] = file
            } else if PairingRule.isRaw(file.name) || ServerFolderListing.isImage(file.name) {
                photos.append(file)
            }
        }
        let units = PairingRule.units(photos, pairs: true, name: \.name, folder: \.folder)
        // A WAV with no photo of its name is not a photo: it stays on the card.
        let items = units.map { unit in
            CardItem(kind: .photo, files: [unit.primary] + (unit.companion.map { [$0] } ?? [])
                     + (audio[pairKey(unit.primary)].map { [$0] } ?? []))
        } + movies.map { CardItem(kind: .video, files: [$0]) }
        return items.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?) where x != y: x < y
            case (_?, nil): true
            case (nil, _?): false
            default: a.id < b.id
            }
        }
    }
}

extension CardCatalog {
    /// Not hidden, not under the camera's MISC folder.
    static func isListed(_ file: CardFile) -> Bool {
        let components = file.path.split(separator: "/")
        if components.contains(where: { $0.hasPrefix(".") }) { return false }
        return !components.dropLast().contains { $0.caseInsensitiveCompare("MISC") == .orderedSame }
    }

    /// Folder and name without extension, case-folded: how a WAV finds its photo.
    static func pairKey(_ file: CardFile) -> String {
        file.folder.lowercased() + "/" + (file.name as NSString).deletingPathExtension.lowercased()
    }
}
