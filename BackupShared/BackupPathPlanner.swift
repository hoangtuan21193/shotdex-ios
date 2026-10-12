import Foundation

/// One file a backup is about to place, reduced to what decides its path.
struct BackupPlacementInput: Sendable {
    /// Date taken; the creation or modification date when there is none.
    var date: Date
    var isVideo: Bool
    /// File name at the source, extension included (`IMG_8812.HEIC`).
    var originalFilename: String
    /// The edited render of an item rather than its original (FS-22.01 §5).
    var isEditedVersion = false
    /// A camera RAW file (CR3, ARW, DNG…) — may go to its own folder.
    var isRAW = false
    /// The album (Photos) or subfolder (FS-19) the Album level files it under;
    /// nil = not in one.
    var album: String?
}

/// Turns a job's Organize settings into a destination path (FS-22.01 §3–§5).
/// Pure, so every combination is a unit test.
struct BackupPathPlanner: Sendable {
    var organize: BackupOrganize
    var names: BackupDateName

    static let videosFolder = "Videos"
    static let rawFolder = "RAW"
    static let unfiledFolder = "Unfiled"

    /// Video placements the Organize menu offers for `levels` (FS-22.01 §4).
    static func videoPlacements(for levels: BackupOrganize.Levels) -> [BackupOrganize.VideoPlacement] {
        switch levels {
        case .yearMonthDay: [.together, .apartAtTop, .apartInYear, .apartInMonth, .apartInDay]
        case .yearMonth: [.together, .apartAtTop, .apartInYear, .apartInMonth]
        case .yearDate: [.together, .apartAtTop, .apartInYear, .apartInDay]
        case .dateOnly: [.together, .apartAtTop, .apartInDay]
        case .album, .noFolders: [.together, .apartAtTop]
        }
    }

    /// The path under the job's folder, `/`-separated: folders, then the file.
    func relativePath(for input: BackupPlacementInput) -> String {
        (folders(for: input) + [fileName(for: input)]).joined(separator: "/")
    }

    func folders(for input: BackupPlacementInput) -> [String] {
        let date = input.date
        let year = names.year(date, style: organize.yearStyle)
        // Each date folder, tagged with the placement that puts Videos after it.
        var levels: [(name: String, videosAfter: BackupOrganize.VideoPlacement?)] = switch organize.levels {
        case .yearMonthDay: [(year, .apartInYear), (names.month(date, organize: organize), .apartInMonth), (names.day(date, organize: organize), .apartInDay)]
        case .yearMonth: [(year, .apartInYear), (names.month(date, organize: organize), .apartInMonth)]
        case .yearDate: [(year, .apartInYear), (names.day(date, organize: organize), .apartInDay)]
        case .dateOnly: [(names.day(date, organize: organize), .apartInDay)]
        case .album: [(input.album.map(BackupDateName.safeFolderName) ?? Self.unfiledFolder, nil)]
        case .noFolders: []
        }
        levels = levels.map { (BackupDateName.safeFolderName($0.name), $0.videosAfter) }

        let apart: (folder: String, placement: BackupOrganize.VideoPlacement)? =
            input.isVideo ? (Self.videosFolder, organize.videoPlacement)
            : input.isRAW && !input.isEditedVersion ? (Self.rawFolder, organize.rawPlacement)
            : nil
        guard let apart, apart.placement != .together else { return levels.map(\.name) }
        // A placement the levels do not offer falls back to the top.
        let placement = Self.videoPlacements(for: organize.levels).contains(apart.placement)
            ? apart.placement : .apartAtTop
        if placement == .apartAtTop { return [apart.folder] + levels.map(\.name) }
        var result: [String] = []
        for level in levels {
            result.append(level.name)
            if level.videosAfter == placement { result.append(apart.folder) }
        }
        return result
    }

    /// File Names (FS-22.01 §5): every file of an item shares one stem and
    /// keeps its own extension; an edited render adds `_edited`.
    func fileName(for input: BackupPlacementInput) -> String {
        let original = input.originalFilename as NSString
        let ext = original.pathExtension
        let originalStem = original.deletingPathExtension
        var stem = switch organize.fileNames {
        case .original: originalStem
        case .dateAndTime: names.timestamp(input.date)
        case .dateAndOriginal: "\(names.timestamp(input.date)) \(originalStem)"
        }
        if input.isEditedVersion { stem += "_edited" }
        stem = String(stem.map { BackupDateName.forbiddenCharacters.contains($0) ? "-" : $0 })
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }
}
