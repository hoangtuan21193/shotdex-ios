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
/// a folder source (`PairingRule`). Oldest first.
enum CardCatalog {
    static func items(_ files: [CardFile]) -> [CardItem] {
        let units = PairingRule.units(files, pairs: true, name: \.name, folder: \.folder)
        let items = units.map { unit in
            CardItem(kind: .photo, files: [unit.primary] + (unit.companion.map { [$0] } ?? []))
        }
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
