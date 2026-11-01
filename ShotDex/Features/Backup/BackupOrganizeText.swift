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

    static func levels(_ levels: BackupOrganize.Levels) -> String {
        switch levels {
        case .yearMonthDay: String(localized: "Year › Month › Day", comment: "Organize levels")
        case .yearMonth: String(localized: "Year › Month", comment: "Organize levels")
        case .yearDate: String(localized: "Year › Date", comment: "Organize levels")
        case .dateOnly: String(localized: "Date Only", comment: "Organize levels")
        case .album: String(localized: "Album", comment: "Organize levels")
        case .noFolders: String(localized: "No Folders", comment: "Organize levels")
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
