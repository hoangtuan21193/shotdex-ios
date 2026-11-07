import Foundation

/// Words and example paths for Organize choices (FS-22.01 §3–§5).
enum BackupOrganizeText {
    /// The sample the menus and the preview are drawn from.
    static let sampleDate = Date(timeIntervalSince1970: 1_760_277_807)
    static let sampleVideo = "IMG_8813.MOV"

    static var names: BackupDateName { BackupDateName() }

    static func content(_ content: BackupSettings.Content) -> String {
        switch content {
        case .photosAndVideos: String(localized: "Photos & Videos", comment: "Backup: what to copy")
        case .photosOnly: String(localized: "Photos Only", comment: "Backup: what to copy")
        case .videosOnly: String(localized: "Videos Only", comment: "Backup: what to copy")
        }
    }

    /// `Year › Month › Day · videos apart`.
    static func summary(_ organize: BackupOrganize) -> String {
        let videos = organize.videoPlacement == .together
            ? String(localized: "videos together", comment: "Organize summary: photos and videos share folders")
            : String(localized: "videos apart", comment: "Organize summary: videos in their own folder")
        return organize.levels == .noFolders ? levels(organize.levels) : "\(levels(organize.levels)) · \(videos)"
    }

    /// `2025 › Oct › 2025.10.12 › IMG_8812.HEIC` — where a photo lands.
    static func sampleTree(_ organize: BackupOrganize) -> String {
        let planner = BackupPathPlanner(organize: organize, names: names)
        let input = BackupPlacementInput(date: sampleDate, isVideo: false, originalFilename: "IMG_8812.HEIC", album: String(localized: "Trip", comment: "Organize preview: sample album name"))
        return (planner.folders(for: input) + [planner.fileName(for: input)]).joined(separator: " › ")
    }

    /// Find Common Photos' example (FS-19.08 §6e): a RAW the first folder
    /// keeps in `2025/10/12`, as `organize` files it —
    /// `2025/10/12/DSC04388.ARW` for Same as Source.
    static func commonPhotosSample(_ organize: BackupOrganize) -> String {
        commonPhotosPath(organize, name: "DSC04388.ARW", sourceFolder: "2025/10/12").joined(separator: "/")
    }

    /// The Organize page's preview for Find Common Photos: a photo the first
    /// folder keeps in `2025/03/15`.
    static func commonPhotosTree(_ organize: BackupOrganize) -> String {
        commonPhotosPath(organize, name: "IMG_4021.HEIC", sourceFolder: "2025/03/15").joined(separator: " › ")
    }

    private static func commonPhotosPath(_ organize: BackupOrganize, name: String, sourceFolder: String) -> [String] {
        let planner = BackupPathPlanner(organize: organize, names: names)
        let input = BackupPlacementInput(date: sampleDate, isVideo: false, originalFilename: name,
                                         isRAW: FileTypeBadge.isRAW(filename: name), sourceFolder: sourceFolder)
        return planner.folders(for: input) + [planner.fileName(for: input)]
    }

    static func levels(_ levels: BackupOrganize.Levels) -> String {
        switch levels {
        case .yearMonthDay: String(localized: "Year › Month › Day", comment: "Organize levels")
        case .yearMonth: String(localized: "Year › Month", comment: "Organize levels")
        case .yearDate: String(localized: "Year › Date", comment: "Organize levels")
        case .dateOnly: String(localized: "Date Only", comment: "Organize levels")
        case .album: String(localized: "Album", comment: "Organize levels")
        case .noFolders: String(localized: "No Folders", comment: "Organize levels")
        case .sameAsSource: String(localized: "Same as Source", comment: "Organize levels: Common Photos keeps the first folder's subfolders (FS-19.08 §6e)")
        }
    }

    static func videos(_ placement: BackupOrganize.VideoPlacement) -> String {
        switch placement {
        case .together: String(localized: "Together", comment: "Organize: photos and videos in the same folders")
        case .apartAtTop: String(localized: "Apart at the Top", comment: "Organize: a Videos folder at the top")
        case .apartInYear: String(localized: "Apart in Each Year", comment: "Organize: a Videos folder inside each year")
        case .apartInMonth: String(localized: "Apart in Each Month", comment: "Organize: a Videos folder inside each month")
        case .apartInDay: String(localized: "Apart in Each Day", comment: "Organize: a Videos folder inside each day")
        }
    }

    static func fileNames(_ names: BackupOrganize.FileNames) -> String {
        switch names {
        case .original: String(localized: "Original", comment: "Organize: keep the original file name")
        case .dateAndTime: String(localized: "Date and Time", comment: "Organize: name files by when they were taken")
        case .dateAndOriginal: String(localized: "Date and Original", comment: "Organize: date then the original name")
        }
    }
}

/// The merged tree behind the preview: folders first, then files, in the
/// order the paths reach them.
enum BackupPreviewTree {
    struct Row: Equatable {
        var name: String
        var depth: Int
        var isFolder: Bool
        var symbol: String
    }

    static let samples: [(BackupPlacementInput, String)] = [
        (BackupPlacementInput(date: BackupOrganizeText.sampleDate, isVideo: false, originalFilename: "IMG_8812.HEIC",
                              album: String(localized: "Trip", comment: "Organize preview: sample album name")), "photo"),
        (BackupPlacementInput(date: BackupOrganizeText.sampleDate, isVideo: false, originalFilename: "IMG_8812.CR3", isRAW: true,
                              album: String(localized: "Trip", comment: "Organize preview: sample album name")), "camera.aperture"),
        (BackupPlacementInput(date: BackupOrganizeText.sampleDate, isVideo: true, originalFilename: BackupOrganizeText.sampleVideo,
                              album: String(localized: "Trip", comment: "Organize preview: sample album name")), "video"),
    ]

    static func rows(organize: BackupOrganize) -> [Row] {
        let planner = BackupPathPlanner(organize: organize, names: BackupOrganizeText.names)
        final class Node {
            var children: [(String, Node)] = []
            var files: [(String, String)] = []
            func child(_ name: String) -> Node {
                if let found = children.first(where: { $0.0 == name }) { return found.1 }
                let node = Node()
                children.append((name, node))
                return node
            }
        }
        let root = Node()
        for (input, symbol) in samples {
            var node = root
            for folder in planner.folders(for: input) { node = node.child(folder) }
            node.files.append((planner.fileName(for: input), symbol))
        }
        var rows: [Row] = []
        func walk(_ node: Node, depth: Int) {
            for (name, symbol) in node.files { rows.append(Row(name: name, depth: depth, isFolder: false, symbol: symbol)) }
            for (name, child) in node.children {
                rows.append(Row(name: name, depth: depth, isFolder: true, symbol: "folder"))
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return rows
    }
}
